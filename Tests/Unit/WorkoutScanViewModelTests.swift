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

        viewModel.addExercise()
        XCTAssertEqual(viewModel.draft.exercises.count, 2)

        viewModel.removeExercise(withID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises.count, 1)
    }
}
