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

    // MARK: - Unparsed lines

    func testPreviewSurfacesUnparsedLines() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185\nround 2 of 3 felt easy"

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.unparsedLines, ["round 2 of 3 felt easy"])
    }

    func testPreviewWithoutDropsHasNoUnparsedLines() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Push day\nBench 3x8 @ 185 rest 90s"

        await viewModel.preview(in: context)

        XCTAssertTrue(viewModel.unparsedLines.isEmpty)
    }

    func testRetryUnparsedLineJoinsDraftWhenFixed() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185\nround 2 of 3 felt easy"
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.draft.exercises.count, 1)

        await viewModel.retryUnparsedLine(at: 0, replacement: "Squat 5x5 @ 225")

        XCTAssertTrue(viewModel.unparsedLines.isEmpty)
        XCTAssertEqual(viewModel.draft.exercises.count, 2)
        XCTAssertEqual(viewModel.draft.exercises[1].name, "Squat")
        XCTAssertNotNil(viewModel.resolution(for: viewModel.draft.exercises[1].id))
    }

    func testRetryUnparsedLineStaysListedWhenStillUnparseable() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185\nround 2 of 3 felt easy"
        await viewModel.preview(in: context)

        await viewModel.retryUnparsedLine(at: 0, replacement: "still not notation honestly")

        XCTAssertEqual(viewModel.unparsedLines, ["still not notation honestly"])
        XCTAssertEqual(viewModel.draft.exercises.count, 1)
    }

    // MARK: - Live preview

    func testLivePreviewRecognizesAndFlagsLines() {
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185\nround 2 of 3 felt easy"

        viewModel.updateLivePreview()

        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.name), ["Bench"])
        XCTAssertEqual(viewModel.livePreview?.recognized.first?.setCount, 3)
        XCTAssertEqual(viewModel.livePreview?.unrecognized, ["round 2 of 3 felt easy"])
    }

    func testLivePreviewClearsOnEmptyText() {
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8"
        viewModel.updateLivePreview()
        XCTAssertNotNil(viewModel.livePreview)

        viewModel.text = "  "
        viewModel.updateLivePreview()
        XCTAssertNil(viewModel.livePreview)
    }

    // MARK: - Preferred weight unit

    func testUnitlessWeightsUseInjectedDefaultUnit() async {
        let context = makeInMemoryContext()
        let viewModel = WorkoutTextEntryViewModel(
            parser: HeuristicWorkoutScanParser(defaultWeightUnit: .kg),
            defaultWeightUnit: .kg
        )
        viewModel.text = "Bench 3x8 @ 100"

        await viewModel.preview(in: context)

        XCTAssertTrue(viewModel.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg })
    }

    // MARK: - Parse progress

    /// Emits every pipeline stage like the on-device parser does, so the view
    /// model's progress plumbing is verifiable without Apple Intelligence.
    private struct StageStubParser: WorkoutScanParsing {
        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            ParsedWorkoutDraft(exercises: [
                ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(reps: 5)])
            ])
        }

        func parse(
            ocrText: String,
            referenceDate: Date,
            onStage: @Sendable (WorkoutParseStage) async -> Void
        ) async -> ParsedWorkoutDraft {
            await onStage(.readingNotation)
            await onStage(.interpreting(pass: 1, of: 2))
            await onStage(.interpreting(pass: 2, of: 2))
            await onStage(.finalizing)
            return await parse(ocrText: ocrText, referenceDate: referenceDate)
        }
    }

    func testParseStageTracksParserCallbacksAndEndsFinalizing() async {
        let context = makeInMemoryContext()
        let viewModel = WorkoutTextEntryViewModel(parser: StageStubParser())
        viewModel.text = "Bench 1x5"
        XCTAssertEqual(viewModel.parseStage, .readingNotation)

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.parseStage, .finalizing,
                       "The stub's last stage (finalizing) must be reflected on the view model")
    }

    // MARK: - Reordering

    func testMoveExerciseReordersDraft() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8\nSquat 5x5\nRow 3x10"
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Squat", "Row"])

        let rowID = viewModel.draft.exercises[2].id
        viewModel.moveExercise(withID: rowID, by: -1)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Row", "Squat"])

        // Out-of-range moves are no-ops.
        viewModel.moveExercise(withID: viewModel.draft.exercises[0].id, by: -1)
        XCTAssertEqual(viewModel.draft.exercises.map(\.name), ["Bench", "Row", "Squat"])
        XCTAssertEqual(viewModel.exerciseIndex(withID: rowID), 1)
    }

    // MARK: - Import celebration

    func testCelebrationReportsTotalVolumeInPreferredUnit() async {
        let context = makeInMemoryContext()
        let viewModel = WorkoutTextEntryViewModel(
            parser: HeuristicWorkoutScanParser(defaultWeightUnit: .lb),
            defaultWeightUnit: .lb
        )
        viewModel.text = "Bench 3x8 @ 185"

        await viewModel.preview(in: context)
        viewModel.commit(into: context)

        XCTAssertEqual(viewModel.phase, .imported)
        XCTAssertEqual(viewModel.celebration.volumeText, "4,440 lb")
        XCTAssertTrue(viewModel.celebration.prExercises.isEmpty,
                      "A brand-new exercise has no record to beat")
    }

    func testCelebrationDetectsBeatenRecords() async {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        context.insert(SetEntry(
            exercise: existing,
            performedAt: Date(timeIntervalSinceNow: -86400),
            weight: 135,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        ))
        try? context.save()
        let viewModel = WorkoutTextEntryViewModel(
            parser: HeuristicWorkoutScanParser(defaultWeightUnit: .lb),
            defaultWeightUnit: .lb
        )
        viewModel.text = "bench press 1x5 @ 225"

        await viewModel.preview(in: context)
        viewModel.commit(into: context)

        XCTAssertEqual(viewModel.celebration.prExercises, ["Bench Press"])
    }

    func testCelebrationStaysQuietWhenNoRecordBeaten() async {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        context.insert(SetEntry(
            exercise: existing,
            performedAt: Date(timeIntervalSinceNow: -86400),
            weight: 225,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        ))
        try? context.save()
        let viewModel = WorkoutTextEntryViewModel(
            parser: HeuristicWorkoutScanParser(defaultWeightUnit: .lb),
            defaultWeightUnit: .lb
        )
        viewModel.text = "bench press 1x3 @ 100"

        await viewModel.preview(in: context)
        viewModel.commit(into: context)

        XCTAssertTrue(viewModel.celebration.prExercises.isEmpty)
        XCTAssertEqual(viewModel.celebration.volumeText, "300 lb")
    }

    // MARK: - Bulk sessions

    func testMultiDayPasteEntersBatchReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertEqual(viewModel.sessions.map(\.draft.importableExercises.first?.name), ["Bench", "Squat"])
        XCTAssertTrue(viewModel.sessions.allSatisfy(\.selected))
        XCTAssertEqual(viewModel.selectedSetCount, 8)
    }

    func testBatchCommitImportsTwoWorkoutsAndLinksLedger() async throws {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """
        await viewModel.preview(in: context)
        viewModel.commitSelected(into: context)

        XCTAssertEqual(viewModel.phase, .imported)
        XCTAssertEqual(viewModel.lastSummary?.importedWorkouts, 2)
        XCTAssertEqual(viewModel.lastSummary?.importedSets, 8)

        let ledgers = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(ledgers.count, 2)
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(entries.count, 8)
        XCTAssertTrue(entries.allSatisfy { $0.importedWorkout != nil })
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 2)
    }

    func testDeselectedSessionIsNotImported() async throws {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """
        await viewModel.preview(in: context)
        let squatID = try XCTUnwrap(viewModel.sessions.last?.id)
        viewModel.toggleSessionSelected(squatID)
        viewModel.commitSelected(into: context)

        XCTAssertEqual(viewModel.lastSummary?.importedWorkouts, 1)
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.exercise.name == "Bench" })
    }

    func testReimportingSameSegmentMarksAlreadyImportedAndSkips() async throws {
        let context = makeInMemoryContext()
        let paste = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """
        let first = makeViewModel()
        first.text = paste
        await first.preview(in: context)
        first.commitSelected(into: context)

        let second = makeViewModel()
        second.text = paste
        await second.preview(in: context)
        XCTAssertEqual(second.phase, .batchReview)
        XCTAssertTrue(second.sessions.allSatisfy(\.alreadyImported))
        XCTAssertTrue(second.importableSelectedSessions.isEmpty)

        second.selectAllImportable()
        second.commitSelected(into: context)
        XCTAssertEqual(second.lastSummary?.importedWorkouts, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ImportedWorkout>()).count, 2)
    }

    func testHevyCSVPasteEntersBatchReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2025-01-15 18:00:00,Bench Press,0,185,8
        Pull Day,2025-01-16 18:00:00,Row,0,135,10
        """

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertEqual(viewModel.sessions.map(\.kind), [.hevyCSV, .hevyCSV])
        XCTAssertEqual(viewModel.sessions[0].draft.title, "Push Day")
    }

    func testSingleWorkoutStillOpensReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185"
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.sessions.count, 1)
    }

    func testDrillInAndReturnPersistEdits() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5
        """
        await viewModel.preview(in: context)
        let firstID = viewModel.sessions[0].id
        viewModel.openSession(firstID)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertTrue(viewModel.isDrillingInFromBatch)
        viewModel.draft.title = "Renamed Push"
        viewModel.returnToBatch()
        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.sessions[0].draft.title, "Renamed Push")
    }

    func testIngestPastedTextAppends() {
        let viewModel = makeViewModel()
        viewModel.ingestPastedText("Bench 3x8")
        viewModel.ingestPastedText("Squat 5x5")
        XCTAssertTrue(viewModel.text.contains("Bench 3x8"))
        XCTAssertTrue(viewModel.text.contains("Squat 5x5"))
    }

    func testSingleCSVWorkoutOpensReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2025-01-15 18:00:00,Bench Press,0,185,8
        """
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.title, "Push Day")
        XCTAssertEqual(viewModel.sessions.count, 1)
    }

    func testLivePreviewTreatsCSVAsWorkoutsNotNotationLines() {
        let viewModel = makeViewModel()
        viewModel.text = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2025-01-15 18:00:00,Bench Press,0,185,8
        Pull Day,2025-01-16 18:00:00,Row,0,135,10
        """
        viewModel.updateLivePreview()
        XCTAssertEqual(viewModel.livePreview?.sessionCount, 2)
        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.name), ["Push Day", "Pull Day"])
        XCTAssertTrue(viewModel.livePreview?.unrecognized.isEmpty ?? false)
    }

    func testIngestSourcesMergesCSVHeaders() {
        let viewModel = makeViewModel()
        viewModel.ingestPastedText("""
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2025-01-15 18:00:00,Bench Press,0,185,8
        """)
        viewModel.ingestPastedText("""
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Pull Day,2025-01-16 18:00:00,Row,0,135,10
        """)
        viewModel.updateLivePreview()
        XCTAssertEqual(viewModel.livePreview?.sessionCount, 2)
        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.name), ["Push Day", "Pull Day"])
    }

    func testToggleSelectAllDeselectsImportableSessions() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """
        await viewModel.preview(in: context)
        XCTAssertTrue(viewModel.allImportableSelected)
        viewModel.toggleSelectAllImportable()
        XCTAssertTrue(viewModel.importableSelectedSessions.isEmpty)
        viewModel.toggleSelectAllImportable()
        XCTAssertEqual(viewModel.importableSelectedSessions.count, 2)
    }

    func testWeekdayPasteEntersBatchReview() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        Monday
        Bench 3x8 @ 185

        Tuesday
        Squat 5x5
        """
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.sessions.count, 2)
    }
}

@MainActor
final class PendingTextImportTests: MarbleTestCase {
    override func tearDown() {
        _ = PendingTextImport.consume()
        super.tearDown()
    }

    func testStageThenConsumeReturnsText() {
        PendingTextImport.stage("  Bench 3x8  ")
        XCTAssertTrue(PendingTextImport.hasPending)
        XCTAssertEqual(PendingTextImport.consume(), "  Bench 3x8  ")
        XCTAssertFalse(PendingTextImport.hasPending)
        XCTAssertNil(PendingTextImport.consume())
    }

    func testReviewWorkoutTextIntentStagesPendingPaste() async throws {
        var intent = ReviewWorkoutTextIntent()
        intent.text = "Squat 5x5"
        _ = try await intent.perform()
        XCTAssertEqual(PendingTextImport.consume(), "Squat 5x5")
    }
}
