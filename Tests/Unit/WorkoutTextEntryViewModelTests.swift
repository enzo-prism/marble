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

    func testCommitHonorsCreateNewWhenAnExactLibraryNameExists() async throws {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "Bench Press 3x8 @ 185"

        await viewModel.preview(in: context)
        let exerciseID = try XCTUnwrap(viewModel.draft.exercises.first?.id)
        viewModel.choose(.createNew, for: exerciseID)
        viewModel.commit(into: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(exercises.filter { $0.name == "Bench Press" }.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.exercise.id != existing.id })
        XCTAssertTrue(viewModel.text.isEmpty, "Saved source text must not remain as an appendable draft")
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

    private struct YieldingRetryParser: WorkoutScanParsing {
        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            if ocrText.contains("Bench 3x8") {
                return ParsedWorkoutDraft(exercises: [
                    ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(reps: 8)])
                ])
            }
            // Keep both retries in flight so identical source strings exercise
            // row identity instead of accidentally passing via serial timing.
            try? await Task.sleep(for: .milliseconds(20))
            let name = ocrText.contains("Squat") ? "Squat" : "Row"
            return ParsedWorkoutDraft(exercises: [
                ParsedExerciseDraft(name: name, sets: [ParsedSetDraft(reps: 5)])
            ])
        }
    }

    func testConcurrentRetriesKeepIdenticalUnparsedRowsDistinct() async {
        let context = makeInMemoryContext()
        let viewModel = WorkoutTextEntryViewModel(parser: YieldingRetryParser())
        viewModel.text = "Bench 3x8\nround 2 of 3 felt easy\nround 2 of 3 felt easy"
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.unparsedLines, ["round 2 of 3 felt easy", "round 2 of 3 felt easy"])

        let first = Task { @MainActor in
            await viewModel.retryUnparsedLine(at: 0, replacement: "Squat 1x5")
        }
        await Task.yield()
        let second = Task { @MainActor in
            await viewModel.retryUnparsedLine(at: 1, replacement: "Row 1x5")
        }
        await first.value
        await second.value

        XCTAssertTrue(viewModel.unparsedLines.isEmpty)
        XCTAssertEqual(Set(viewModel.draft.exercises.map(\.name)), ["Bench", "Squat", "Row"])
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

    func testLivePreviewDoesNotInventWorkoutFromTrailingNote() {
        let viewModel = makeViewModel()
        viewModel.text = "Bench Press 3x8 @ 185 lb\nFelt strong today"

        viewModel.updateLivePreview()

        XCTAssertEqual(viewModel.livePreview?.sessionCount, 1)
        XCTAssertEqual(viewModel.livePreview?.totalSets, 3)
        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.name), ["Bench Press"])
        XCTAssertTrue(viewModel.livePreview?.unrecognized.isEmpty ?? false)
    }

    func testLivePreviewKeepsDelimitedSessionCountWhenOneSessionIsUnrecognized() {
        let viewModel = makeViewModel()
        viewModel.text = """
        Monday
        Bench Press 3x8 @ 185 lb

        Tuesday
        Movement details unavailable
        """

        viewModel.updateLivePreview()

        XCTAssertEqual(viewModel.livePreview?.sessionCount, 2)
        XCTAssertEqual(viewModel.livePreview?.recognized.count, 1)
        XCTAssertEqual(viewModel.livePreview?.totalSets, 3)
        XCTAssertTrue(
            viewModel.livePreview?.unrecognized.contains("Movement details unavailable") ?? false
        )
    }

    func testMultiSessionLivePreviewKeepsDropsFromRecognizedSession() {
        let viewModel = makeViewModel()
        viewModel.text = """
        Monday
        Bench Press 3x8 @ 185 lb
        round 2 of 3 felt easy

        Tuesday
        Squat 5x5 @ 225 lb
        """

        viewModel.updateLivePreview()

        XCTAssertEqual(viewModel.livePreview?.sessionCount, 2)
        XCTAssertEqual(viewModel.livePreview?.recognized.count, 2)
        XCTAssertEqual(viewModel.livePreview?.totalSets, 8)
        XCTAssertEqual(viewModel.livePreview?.unrecognized, ["round 2 of 3 felt easy"])
    }

    func testDebouncedLivePreviewNeverPublishesStaleText() async {
        let viewModel = makeViewModel()
        let staleText = "Bench 3x8 @ 185"
        viewModel.text = staleText
        let staleUpdate = Task { @MainActor in
            await viewModel.updateLivePreview(
                for: staleText,
                debounce: .milliseconds(30)
            )
        }

        await Task.yield()
        let currentText = "Squat 5x5 @ 225"
        viewModel.text = currentText
        await viewModel.updateLivePreview(for: currentText, debounce: .zero)
        await staleUpdate.value

        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.name), ["Squat"])
        XCTAssertEqual(viewModel.livePreview?.totalSets, 5)
    }

    func testLivePreviewRowIdentityIsStableAcrossEquivalentParses() {
        let viewModel = makeViewModel()
        viewModel.text = "Bench 3x8 @ 185\nBench 2x5 @ 205"

        viewModel.updateLivePreview()
        let firstIDs = viewModel.livePreview?.recognized.map(\.id)
        XCTAssertFalse(firstIDs?.isEmpty ?? true)
        viewModel.updateLivePreview()

        XCTAssertEqual(viewModel.livePreview?.recognized.map(\.id), firstIDs)
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

    private actor RecordingParser: WorkoutScanParsing {
        private(set) var parseCallCount = 0

        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            parseCallCount += 1
            return ParsedWorkoutDraft(exercises: [
                ParsedExerciseDraft(name: "Unexpected model result", sets: [ParsedSetDraft(reps: 1)])
            ])
        }
    }

    func testParseStageTracksParserCallbacksAndEndsFinalizing() async {
        let context = makeInMemoryContext()
        let viewModel = WorkoutTextEntryViewModel(parser: StageStubParser())
        viewModel.text = "I did a hard workout this morning"
        XCTAssertEqual(viewModel.parseStage, .readingNotation)

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.parseStage, .finalizing,
                       "The stub's last stage (finalizing) must be reflected on the view model")
    }

    func testCompleteNotationUsesDeterministicFastPathWithoutModelParser() async {
        let context = makeInMemoryContext()
        let parser = RecordingParser()
        let viewModel = WorkoutTextEntryViewModel(parser: parser)
        viewModel.text = "Bench Press 3x8 @ 185 lb rest 90s"

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.exercises.first?.name, "Bench Press")
        XCTAssertEqual(viewModel.draft.exercises.first?.sets.count, 3)
        let parseCallCount = await parser.parseCallCount
        XCTAssertEqual(parseCallCount, 0,
                       "A complete notation parse should not invoke the model parser")
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
        let viewModel = makeViewModel()
        viewModel.text = "Bench Press 1x5 @ 225 lb"

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

    func testCelebrationStaysQuietWhenReviewCreatesDuplicateExercise() async {
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
            importHandler: { _, _, _ in
                WorkoutImporter.Summary(importedWorkouts: 1, importedSets: 1)
            },
            defaultWeightUnit: .lb
        )
        viewModel.draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(
                name: "Bench Press",
                sets: [ParsedSetDraft(weight: 225, weightUnit: .lb, reps: 5)],
                createsNewLibraryExercise: true
            )
        ])

        viewModel.commit(into: context)

        XCTAssertTrue(viewModel.celebration.prExercises.isEmpty)
    }

    func testCelebrationUsesReviewedLibraryIDForDuplicateNames() async {
        let context = makeInMemoryContext()
        let unselected = insertExercise("Bench Press", in: context)
        let selected = insertExercise("Bench Press", in: context)
        context.insert(SetEntry(
            exercise: unselected,
            performedAt: Date(timeIntervalSinceNow: -86400),
            weight: 135,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        ))
        context.insert(SetEntry(
            exercise: selected,
            performedAt: Date(timeIntervalSinceNow: -86400),
            weight: 315,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        ))
        try? context.save()
        let viewModel = WorkoutTextEntryViewModel(
            importHandler: { _, _, _ in
                WorkoutImporter.Summary(importedWorkouts: 1, importedSets: 1)
            },
            defaultWeightUnit: .lb
        )
        viewModel.draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(
                name: "Bench Press",
                sets: [ParsedSetDraft(weight: 225, weightUnit: .lb, reps: 5)],
                libraryExerciseID: selected.id
            )
        ])

        viewModel.commit(into: context)

        XCTAssertTrue(viewModel.celebration.prExercises.isEmpty)
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

    func testMultiDayPastePreservesUnreadableSessionAndBlocksImport() async throws {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        Monday
        Bench Press 3x8 @ 185 lb

        Tuesday
        Movement details unavailable
        """

        await viewModel.preview(in: context)

        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertTrue(viewModel.sessions[0].draft.hasContent)
        XCTAssertFalse(viewModel.sessions[1].draft.hasContent)
        XCTAssertFalse(viewModel.sessions[1].selected)
        XCTAssertEqual(viewModel.sessions[1].unparsedLines, ["Movement details unavailable"])
        XCTAssertEqual(viewModel.unresolvedSessionCount, 1)
        XCTAssertFalse(viewModel.canCommitSelectedSessions)

        viewModel.toggleSessionSelected(viewModel.sessions[1].id)
        XCTAssertFalse(viewModel.sessions[1].selected)

        viewModel.commitSelected(into: context)
        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetEntry>()).isEmpty)
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

    func testNewExerciseCountIsUniqueAcrossSessions() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Face Pull 3x12

        3/6
        Face Pull 3x15
        """
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .batchReview)
        XCTAssertEqual(viewModel.newExerciseCount, 1)
    }

    func testBatchMatchBreakdownSeparatesLibraryNewAndWeak() async {
        let context = makeInMemoryContext()
        insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = """
        3/5
        Bench 3x8 @ 185
        Face Pull 3x12

        3/6
        Squat 5x5
        """
        await viewModel.preview(in: context)
        XCTAssertEqual(viewModel.phase, .batchReview)

        let first = viewModel.matchBreakdown(for: viewModel.sessions[0])
        XCTAssertEqual(first.libraryCount, 0)
        XCTAssertEqual(first.newCount, 2)
        XCTAssertEqual(first.weakMatchCount, 1)
        XCTAssertEqual(first.line, "2 new · 1 weak match")

        let second = viewModel.matchBreakdown(for: viewModel.sessions[1])
        XCTAssertEqual(second.libraryCount, 0)
        XCTAssertEqual(second.newCount, 1)
        XCTAssertEqual(second.line, "1 new")
        XCTAssertEqual(viewModel.newExerciseCount, 3)
    }

    func testLikelyMatchDefaultsToCreateNewButKeepsSuggestion() async {
        let context = makeInMemoryContext()
        let existing = insertExercise("Bench Press", in: context)
        let viewModel = makeViewModel()
        viewModel.text = "bench 3x8 @ 185"

        await viewModel.preview(in: context)

        let exerciseID = viewModel.draft.exercises[0].id
        let resolution = viewModel.resolution(for: exerciseID)
        XCTAssertEqual(resolution?.choice, .createNew)
        XCTAssertEqual(resolution?.autoConfidence, .likely)
        XCTAssertEqual(resolution?.suggestions.first?.candidate.id, existing.id)
        XCTAssertEqual(viewModel.newExerciseCount, 1)
    }

    func testAddSetCopiesNotes() async {
        let context = makeInMemoryContext()
        let viewModel = makeViewModel()
        viewModel.text = "Bench 1x8 @ 185"
        await viewModel.preview(in: context)

        let exerciseID = try! XCTUnwrap(viewModel.draft.exercises.first?.id)
        viewModel.draft.exercises[0].sets[0].notes = "paused"
        viewModel.addSet(toExerciseWithID: exerciseID)
        XCTAssertEqual(viewModel.draft.exercises[0].sets.last?.notes, "paused")
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

    func testReviewWorkoutTextIntentSignalsTheComposer() async throws {
        let notification = expectation(description: "Open workout text composer")
        let observer = NotificationCenter.default.addObserver(
            forName: .marbleOpenTextImport,
            object: nil,
            queue: nil
        ) { _ in
            notification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        var intent = ReviewWorkoutTextIntent()
        intent.text = "Squat 5x5"
        _ = try await intent.perform()
        await fulfillment(of: [notification], timeout: 1)
    }
}
