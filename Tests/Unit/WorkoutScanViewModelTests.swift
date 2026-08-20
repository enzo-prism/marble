import CoreGraphics
import SwiftData
import XCTest
@testable import marble

/// Drives the scan view model end-to-end with a stubbed recognizer and the real
/// deterministic parser + importer, so the orchestration (recognize → parse → review →
/// commit, plus error and dedup paths) is verified without the camera or the model.
@MainActor
final class WorkoutScanViewModelTests: MarbleTestCase {

    private struct StubRecognizer: WorkoutTextRecognizing {
        let text: String?  // nil => throw, simulating an OCR failure
        func recognizeText(in image: CGImage) async throws -> String {
            guard let text else { throw NSError(domain: "test", code: 1) }
            return text
        }
    }

    private final class SequenceRecognizer: WorkoutTextRecognizing, @unchecked Sendable {
        private var remaining: [String]
        init(texts: [String]) { remaining = texts }
        func recognizeText(in image: CGImage) async throws -> String {
            remaining.isEmpty ? "" : remaining.removeFirst()
        }
    }

    private func makeCGImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func makeViewModel(text: String?) -> WorkoutScanViewModel {
        WorkoutScanViewModel(recognizer: StubRecognizer(text: text), parser: HeuristicWorkoutScanParser())
    }

    func testProcessPopulatesDraftAndEntersReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "Squat 5x5")

        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.exercises.count, 1)
        XCTAssertEqual(viewModel.draft.exercises.first?.sets.count, 5)
        XCTAssertFalse(viewModel.externalID.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRecognizerFailureReturnsToCapture() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: nil)

        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        XCTAssertEqual(viewModel.phase, .capture)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCommitImportsAndPersists() async throws {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "Bench 3x5 @ 135")

        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)
        viewModel.commit(into: context)

        XCTAssertEqual(viewModel.phase, .imported)
        XCTAssertEqual(viewModel.lastSummary?.importedSets, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).count, 3)
    }

    func testAlreadyImportedFlagSetOnSecondScanOfSameImage() async {
        let context = makeInMemoryContext()
        let data = Data("identical-page".utf8)

        let first = makeViewModel(text: "Squat 5x5")
        await first.process(cgImage: makeCGImage(), imageData: data, in: context)
        first.commit(into: context)
        XCTAssertEqual(first.phase, .imported)

        let second = makeViewModel(text: "Squat 5x5")
        await second.process(cgImage: makeCGImage(), imageData: data, in: context)
        XCTAssertTrue(second.alreadyImported)
    }

    func testCommitWithEmptyDraftShowsErrorAndStaysInReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "------\n???")

        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertFalse(viewModel.draft.hasContent)

        viewModel.commit(into: context)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testEditingHelpers() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "Squat 5x5")
        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        let exerciseID = try! XCTUnwrap(viewModel.draft.exercises.first?.id)
        let originalSetCount = viewModel.draft.exercises[0].sets.count

        viewModel.addSet(toExerciseWithID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises[0].sets.count, originalSetCount + 1)

        // A new set copies the template's per-set date & time override too.
        let overrideDate = Date(timeIntervalSince1970: 1_750_000_000)
        viewModel.draft.exercises[0].sets[viewModel.draft.exercises[0].sets.count - 1].performedAt = overrideDate
        viewModel.addSet(toExerciseWithID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises[0].sets.last?.performedAt, overrideDate)

        viewModel.addExercise()
        XCTAssertEqual(viewModel.draft.exercises.count, 2)

        viewModel.removeExercise(withID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises.count, 1)
    }

    func testJoinOCRDropsBlankPages() {
        XCTAssertEqual(
            WorkoutScanViewModel.joinOCR(["Monday\nBench 3x8", "  ", "Tuesday\nSquat 5x5"]),
            "Monday\nBench 3x8\n\nTuesday\nSquat 5x5"
        )
    }

    func testMultiPageOCRConcatenatesIntoOneDraft() async {
        let context = makeInMemoryContext()
        let recognizer = SequenceRecognizer(texts: ["Bench 3x8 @ 185", "Squat 5x5"])
        let viewModel = WorkoutScanViewModel(recognizer: recognizer, parser: HeuristicWorkoutScanParser())
        let image = makeCGImage()

        await viewModel.process(
            pages: [(image, Data("page-a".utf8)), (image, Data("page-b".utf8))],
            in: context
        )

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Squat"])
        XCTAssertEqual(viewModel.draft.exercises[0].sets.count, 3)
        XCTAssertEqual(viewModel.draft.exercises[1].sets.count, 5)
    }

    func testMultiSessionOCRHandsOffToTypedPipeline() async {
        let context = makeInMemoryContext()
        let recognizer = SequenceRecognizer(texts: [
            "Monday\nBench 3x8 @ 185",
            "Tuesday\nSquat 5x5 @ 225"
        ])
        let viewModel = WorkoutScanViewModel(recognizer: recognizer, parser: HeuristicWorkoutScanParser())
        let image = makeCGImage()

        await viewModel.process(
            pages: [(image, Data("p1".utf8)), (image, Data("p2".utf8))],
            in: context
        )

        XCTAssertEqual(viewModel.phase, .textHandoff)
        XCTAssertTrue(viewModel.handoffText.contains("Monday"))
        XCTAssertTrue(viewModel.handoffText.contains("Tuesday"))
        XCTAssertTrue(viewModel.draft.exercises.isEmpty)
    }

    func testExactLibraryNameReusesExistingExercise() async throws {
        let context = makeInMemoryContext()
        let existing = Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(existing)
        try context.save()

        let viewModel = makeViewModel(text: "bench press 3x5 @ 135")
        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        let exerciseID = try! XCTUnwrap(viewModel.draft.exercises.first?.id)
        guard case let .library(id, name)? = viewModel.resolution(for: exerciseID)?.choice else {
            return XCTFail("Expected an exact library match")
        }
        XCTAssertEqual(id, existing.id)
        XCTAssertEqual(name, "Bench Press")

        viewModel.commit(into: context)
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.exercise.id == existing.id })
        XCTAssertEqual(viewModel.lastSummary?.createdExercises, 0)
    }

    func testLikelyScanMatchDefaultsToCreateNew() async {
        let context = makeInMemoryContext()
        let existing = Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(existing)

        let viewModel = makeViewModel(text: "Bench 3x5 @ 135")
        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        let exerciseID = try! XCTUnwrap(viewModel.draft.exercises.first?.id)
        XCTAssertEqual(viewModel.resolution(for: exerciseID)?.choice, .createNew)
        XCTAssertEqual(viewModel.resolution(for: exerciseID)?.autoConfidence, .likely)
    }

    func testAddSetCopiesNotesOnScan() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "Squat 5x5")
        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)

        let exerciseID = try! XCTUnwrap(viewModel.draft.exercises.first?.id)
        viewModel.draft.exercises[0].sets[viewModel.draft.exercises[0].sets.count - 1].notes = "belt"
        viewModel.addSet(toExerciseWithID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises[0].sets.last?.notes, "belt")
    }

    func testMoveExerciseReordersScanDraft() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel(text: "Bench 3x8\nSquat 5x5\nRow 3x10")
        await viewModel.process(cgImage: makeCGImage(), imageData: Data("page".utf8), in: context)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Squat", "Row"])

        let rowID = viewModel.draft.exercises[2].id
        viewModel.moveExercise(withID: rowID, by: -1)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Row", "Squat"])

        viewModel.moveExercise(withID: viewModel.draft.exercises[0].id, by: -1)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Row", "Squat"])
        XCTAssertEqual(viewModel.exerciseIndex(withID: rowID), 1)
    }
}
