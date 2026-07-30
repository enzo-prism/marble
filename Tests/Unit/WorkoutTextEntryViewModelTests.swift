import SwiftData
import XCTest
@testable import marble

/// Drives the text-entry view model end-to-end with the real deterministic parser,
/// matcher, and importer, so the orchestration (parse → match → review → commit,
/// plus error, override, and dedup paths) is verified without the on-device model.
@MainActor
final class WorkoutTextEntryViewModelTests: MarbleTestCase {

    private func makeViewModel() -> WorkoutTextEntryViewModel {
        WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser())
    }

    private func insertExercise(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(exercise)
        return exercise
    }

    // MARK: - Parse and review

    func testPreviewParsesTextAndEntersReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Push day\nBench Press 3x8 @ 185 rest 90s\nSquat 5x5"

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.title, "Push day")
        XCTAssertEqual(viewModel.draft.exercises.count, 2)
        XCTAssertEqual(viewModel.draft.exercises.first?.sets.count, 3)
        XCTAssertEqual(viewModel.draft.exercises.first?.sets.first?.restSeconds, 90)
        XCTAssertFalse(viewModel.externalID.isEmpty)
    }

    func testPreviewWithEmptyTextStaysOnInput() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "   \n  "

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .input)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testPreviewWithUnparseableTextStaysOnInputWithGuidance() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "just some words about my day"

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .input)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Matching

    func testLibraryMatchIsAutoResolvedToExistingExercise() async {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "bench press 3x8 @ 185"

        await viewModel.preview(in: context)

        let exerciseID = viewModel.draft.exercises[0].id
        guard case let .library(id, name)? = viewModel.resolution(for: exerciseID)?.choice else {
            return XCTFail("Expected a library match")
        }
        XCTAssertEqual(id, existing.id)
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(viewModel.newExerciseCount, 0)
    }

    func testUnknownExerciseResolvesToCreateNew() async {
        let context = makeInMemoryContext()
        _ = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "Cable Woodchop 3x12"

        await viewModel.preview(in: context)

        let exerciseID = viewModel.draft.exercises[0].id
        XCTAssertEqual(viewModel.resolution(for: exerciseID)?.choice, .createNew)
        XCTAssertEqual(viewModel.newExerciseCount, 1)
    }

    func testChooseOverridesAutoResolution() async {
        let context = makeInMemoryContext()
        _ = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "bench 3x8"

        await viewModel.preview(in: context)
        let exerciseID = viewModel.draft.exercises[0].id

        viewModel.choose(.createNew, for: exerciseID)
        XCTAssertEqual(viewModel.resolution(for: exerciseID)?.choice, .createNew)
        XCTAssertNil(viewModel.resolution(for: exerciseID)?.autoConfidence)
        XCTAssertEqual(viewModel.newExerciseCount, 1)
    }

    func testRefreshResolutionRematchesAfterNameEdit() async {
        let context = makeInMemoryContext()
        _ = insertExercise("Overhead Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "Mystery Movement 3x8"

        await viewModel.preview(in: context)
        let exerciseID = viewModel.draft.exercises[0].id
        XCTAssertEqual(viewModel.resolution(for: exerciseID)?.choice, .createNew)

        let index = viewModel.draft.exercises.firstIndex { $0.id == exerciseID }!
        viewModel.draft.exercises[index].name = "OHP"
        viewModel.refreshResolution(forExerciseWithID: exerciseID)

        guard case let .library(_, name)? = viewModel.resolution(for: exerciseID)?.choice else {
            return XCTFail("Expected a library match after renaming to OHP")
        }
        XCTAssertEqual(name, "Overhead Press")
    }

    // MARK: - Commit

    func testCommitImportsUnderCanonicalLibraryName() async throws {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "bench press 3x8 @ 185 rest 90s"

        await viewModel.preview(in: context)
        viewModel.commit(into: context)

        XCTAssertEqual(viewModel.phase, .imported)
        XCTAssertEqual(viewModel.lastSummary?.importedSets, 3)
        XCTAssertEqual(viewModel.lastSummary?.createdExercises, 0)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.exercise.id == existing.id })
        XCTAssertTrue(entries.allSatisfy { $0.restAfterSeconds == 90 })

        let ledger = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger.first?.source, .textEntry)
    }

    func testCommitCreatesNewExerciseWhenChosen() async throws {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Cable Woodchop 3x12"

        await viewModel.preview(in: context)
        viewModel.commit(into: context)

        XCTAssertEqual(viewModel.phase, .imported)
        XCTAssertEqual(viewModel.lastSummary?.createdExercises, 1)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(exercises.contains { $0.name == "Cable Woodchop" })
    }

    func testSameTextTwiceSetsAlreadyImportedAndSkips() async {
        let context = makeInMemoryContext()

        let first = makeViewModel()
        first.text = "Squat 5x5 @ 225"
        await first.preview(in: context)
        first.commit(into: context)
        XCTAssertEqual(first.phase, .imported)

        let second = makeViewModel()
        second.text = "Squat 5x5 @ 225"
        await second.preview(in: context)
        XCTAssertTrue(second.alreadyImported)

        second.commit(into: context)
        XCTAssertEqual(second.lastSummary?.skipped, 1)
        XCTAssertEqual(second.lastSummary?.importedSets, 0)
    }

    // MARK: - Editing helpers

    func testEditingHelpersKeepResolutionsInSync() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Squat 5x5"
        await viewModel.preview(in: context)

        let exerciseID = viewModel.draft.exercises[0].id

        viewModel.addExercise()
        XCTAssertEqual(viewModel.draft.exercises.count, 2)
        let addedID = viewModel.draft.exercises[1].id
        XCTAssertEqual(viewModel.resolution(for: addedID)?.choice, .createNew)

        viewModel.removeExercise(withID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises.count, 1)
        XCTAssertNil(viewModel.resolution(for: exerciseID))
    }

    func testEditTextReturnsToInputKeepingText() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Squat 5x5"
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .review)

        viewModel.editText()
        XCTAssertEqual(viewModel.phase, .input)
        XCTAssertEqual(viewModel.text, "Squat 5x5")
    }
}
