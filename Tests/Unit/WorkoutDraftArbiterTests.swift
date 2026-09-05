import XCTest
@testable import marble

/// Pins the arbiter's choice between the deterministic notation parse and the
/// on-device model parse: empty-draft fast paths, score-based selection, the
/// deterministic tie-break, cross-draft date/title merging, and the NxM
/// expected-set-count extraction the scoring leans on.
@MainActor
final class WorkoutDraftArbiterTests: MarbleTestCase {

    // MARK: - Draft builders

    private func draft(
        title: String = "Push day",
        performedAt: Date? = nil,
        exercises: [ParsedExerciseDraft]
    ) -> ParsedWorkoutDraft {
        ParsedWorkoutDraft(performedAt: performedAt, title: title, exercises: exercises)
    }

    private func exercise(_ name: String, sets: [ParsedSetDraft]) -> ParsedExerciseDraft {
        ParsedExerciseDraft(name: name, sets: sets)
    }

    private func set(weight: Double? = nil, reps: Int? = nil) -> ParsedSetDraft {
        ParsedSetDraft(weight: weight, reps: reps)
    }

    private func benchSets(count: Int, weight: Double = 185, reps: Int = 8) -> [ParsedSetDraft] {
        (0..<count).map { _ in set(weight: weight, reps: reps) }
    }

    // MARK: - Fast paths

    func testNilModelReturnsDeterministic() {
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: nil, sourceText: "Bench 3x8 @ 185"
        )
        XCTAssertEqual(chosen, deterministic)
    }

    func testEmptyModelReturnsDeterministic() {
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let emptyModel = draft(exercises: [])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: emptyModel, sourceText: "Bench 3x8 @ 185"
        )
        XCTAssertEqual(chosen, deterministic)
    }

    func testEmptyDeterministicReturnsModel() {
        let deterministic = draft(exercises: [])
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model,
            sourceText: "three sets of eight on bench at 185"
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
    }

    // MARK: - Score-based selection

    func testDeterministicWinsWhenModelCollapsesSets() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        // The model read the same line but folded 3x8 into a single set.
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 1))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.totalSetCount, 3)
    }

    func testModelWinsOnProseEvenWithoutDigitMatchedNumbers() {
        // No digits in the text, so numeric fidelity can't reward the model —
        // but the deterministic parser found nothing, so the model must still win.
        let text = "three sets of eight on bench at one eighty five"
        let deterministic = draft(exercises: [])
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
    }

    func testHallucinatedWeightScoresLowerThanFaithfulDraft() {
        let text = "Bench 3x8 @ 185"
        let faithful = draft(exercises: [exercise("Bench", sets: benchSets(count: 3, weight: 185))])
        let hallucinated = draft(exercises: [exercise("Bench", sets: benchSets(count: 3, weight: 999))])
        XCTAssertLessThan(
            WorkoutDraftArbiter.score(hallucinated, against: text),
            WorkoutDraftArbiter.score(faithful, against: text)
        )
    }

    func testTieGoesToDeterministic() {
        // Structurally identical drafts (identical scores) that differ only in
        // exercise naming — the deterministic one must be returned.
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [exercise("Barbell Bench Press", sets: benchSets(count: 3))])
        XCTAssertEqual(
            WorkoutDraftArbiter.score(deterministic, against: text),
            WorkoutDraftArbiter.score(model, against: text)
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].name, "Bench")
    }

    // MARK: - Cross-draft merging

    func testWinnerInheritsLosersDate() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        // Model loses on set count but is the only draft that read the date header.
        let model = draft(
            performedAt: Self.fixedNow,
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.performedAt, Self.fixedNow)
    }

    func testWinnerInheritsLosersRealTitleOverPlaceholder() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(
            title: "Typed workout",
            exercises: [exercise("Bench", sets: benchSets(count: 3))]
        )
        let model = draft(
            title: "Push Day A",
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.title, "Push Day A")
    }

    func testRealTitleIsNotReplacedByLosersTitle() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(
            title: "Upper body",
            exercises: [exercise("Bench", sets: benchSets(count: 3))]
        )
        let model = draft(
            title: "Push Day A",
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.title, "Upper body")
    }

    // MARK: - expectedSetCount

    func testExpectedSetCountSumsSetsByRepsTokens() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3x8 Squat 5x5"), 8)
    }

    func testExpectedSetCountIgnoresWeightByRepsTokens() {
        // 315 is a load, not a set count — above the disambiguation threshold.
        XCTAssertNil(WorkoutDraftArbiter.expectedSetCount(in: "Deadlift 315x5"))
    }

    func testExpectedSetCountNilWithoutNumbers() {
        XCTAssertNil(WorkoutDraftArbiter.expectedSetCount(in: "no numbers here"))
    }

    func testExpectedSetCountHandlesSpacedX() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Plank 3 x 60s"), 3)
    }

    func testExpectedSetCountHandlesUnicodeMultiplicationSign() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3×8"), 3)
    }

    func testModelCannotBorrowAnotherMovementsWeightOrDateNumber() {
        let text = "9/4/26\nBench 3x8 @ 185\nSquat 2 sets"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [
            exercise("Bench", sets: benchSets(count: 3)),
            exercise("Squat", sets: [.init(weight: 185, reps: 26), .init(weight: 185, reps: 26)])
        ])
        let result = WorkoutDraftArbiter.choose(deterministic: deterministic, model: model, sourceText: text)
        XCTAssertEqual(result.exercises.count, 1)
        XCTAssertEqual(result.exercises[0].name, "Bench")
    }

    func testUnsupportedModelExerciseAndInventedNumbersAreRejected() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(),
            model: draft(exercises: [exercise("Bench", sets: [.init(weight: 999, reps: 8)]),
                                     exercise("Squat", sets: [.init(reps: 8)])]),
            sourceText: "Bench 1x8"
        )
        XCTAssertFalse(result.hasContent)
    }

    func testPartialModelDoesNotEraseCorrectDeterministicMovement() {
        let bench = exercise("Bench", sets: benchSets(count: 3))
        let bounds = exercise("Speed Bounds", sets: [.init(), .init()])
        let result = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: [bench]), model: draft(exercises: [bounds]),
            sourceText: "Bench 3x8 @ 185\nSpeed Bounds (2 sets)"
        )
        // Regardless of the winning whole draft, already recognized data survives.
        XCTAssertTrue(result.exercises.contains(bench))
        XCTAssertTrue(result.exercises.contains(bounds))
        XCTAssertEqual(result.totalSetCount, 5)
    }

    func testCountOnlyExercisePreservesAbsentMetrics() {
        let sets = [ParsedSetDraft(), ParsedSetDraft()]
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Speed Bounds", sets: sets)]),
            sourceText: "Speed Bounds (2 sets)"
        )
        XCTAssertEqual(result.totalSetCount, 2)
        XCTAssertTrue(result.exercises[0].sets.allSatisfy { !$0.hasAnyValue })
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Speed Bounds (2 sets)"), 2)
    }

    func testSprintSourceDoesNotResolveToRopeSprint() {
        let text = "Resistance Rope Sprint 2 sets, 50m each\nSprints, 2 sets, 50m each"
        XCTAssertEqual(WorkoutDraftArbiter.sourceSpan(for: "Sprints", in: text)?.index, 1)
        XCTAssertEqual(WorkoutDraftArbiter.sourceSpan(for: "Resistance Rope Sprint", in: text)?.index, 0)
    }


    func testNameRecognitionDoesNotClearUnresolvedFacts() {
        let parsed = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        XCTAssertFalse(WorkoutDraftArbiter.isSourceLineRepresented(
            "Bench 3x8 @ 185; skipped the final set", by: parsed,
            referenceDate: Self.fixedNow, defaultWeightUnit: .lb
        ))
    }

    func testModelBudgetRejectsOversizeWithoutTruncatingInput() {
        XCTAssertTrue(FoundationModelsWorkoutScanParser.canAttemptModel(for: "Sprints 2 sets, 50m each"))
        XCTAssertFalse(FoundationModelsWorkoutScanParser.canAttemptModel(for: String(repeating: "x", count: 4_001)))
        XCTAssertFalse(FoundationModelsWorkoutScanParser.canAttemptModel(for: " \n"))
    }


    func testSurvivingModelDoesNotReorderRepeatedExerciseBlocks() {
        let first = exercise("Squat", sets: [.init(weight: 100, reps: 5), .init(weight: 100, reps: 5)])
        let middle = exercise("Bench", sets: [.init(weight: 60, reps: 8), .init(weight: 60, reps: 8)])
        let last = exercise("Squat", sets: [.init(weight: 110, reps: 3)])
        let original = draft(exercises: [first, middle, last])
        let result = WorkoutDraftArbiter.choose(
            deterministic: original, model: draft(exercises: [middle]),
            sourceText: "Squat 2x5 @ 100\nBench 2x8 @ 60\nSquat 1x3 @ 110"
        )
        XCTAssertEqual(result.exercises, [first, middle, last])
    }


    func testCountCannotBeInventedAsRepetitions() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Bounds", sets: [.init(reps: 2), .init(reps: 2)])]),
            sourceText: "Bounds (2 sets)"
        )
        XCTAssertFalse(result.hasContent)
    }

    func testTimeCannotBeInventedAsWeight() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Run", sets: [.init(weight: 20)])]),
            sourceText: "Run 20min"
        )
        XCTAssertFalse(result.hasContent)
    }

    func testExplicitWeightUnitCannotBeRewritten() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Bench", sets: [.init(weight: 60, weightUnit: .lb, reps: 8)])]),
            sourceText: "Bench 60kg x 8"
        )
        XCTAssertFalse(result.hasContent)
    }

    func testSkippedModelMovementIsNotImported() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Squat", sets: [.init(reps: 5)])]),
            sourceText: "Skipped Squat 1x5"
        )
        XCTAssertFalse(result.hasContent)
    }


    func testTotalDistanceIsNotRepeatedPerSetByModel() {
        let result = WorkoutDraftArbiter.choose(
            deterministic: .init(), model: draft(exercises: [exercise("Sprints", sets: [.init(distance: 100), .init(distance: 100)])]),
            sourceText: "Sprints 2 sets, 100m total"
        )
        XCTAssertFalse(result.hasContent)
    }


    func testModelTitleRequiresLiteralNonExerciseHeading() {
        let source = "9/4/26\nBounds (2 sets)"
        let exercises = [exercise("Bounds", sets: [.init(), .init()])]
        XCTAssertFalse(FoundationModelsWorkoutScanParser.isSourceHeading("Push Day", source: source, exercises: exercises))
        XCTAssertFalse(FoundationModelsWorkoutScanParser.isSourceHeading("Bounds", source: source, exercises: exercises))
        XCTAssertTrue(FoundationModelsWorkoutScanParser.isSourceHeading("Track day", source: "Track day\nBounds (2 sets)", exercises: exercises))
    }

    func testCompleteNotesSkipModelStages() async {
        let recorder = ParseStageRecorder()
        let parsed = await FoundationModelsWorkoutScanParser().parse(
            ocrText: "9/4/26\nBounds (2 sets)\nSprints 2 sets, 50m each",
            referenceDate: Self.fixedNow
        ) { stage in await recorder.append(stage) }
        let stages = await recorder.stages
        XCTAssertEqual(parsed.totalSetCount, 4)
        XCTAssertEqual(stages, [.readingNotation, .finalizing])
    }


    func testBenchAliasDoesNotDuplicateDeterministicExercise() {
        let original = draft(exercises: [exercise("bench", sets: benchSets(count: 3))])
        let result = WorkoutDraftArbiter.choose(
            deterministic: original,
            model: draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))]),
            sourceText: "Yesterday I did three sets of eight on bench at 185 pounds"
        )
        XCTAssertEqual(result.totalSetCount, 3)
        XCTAssertEqual(result.exercises.count, 1)
    }


    func testRepetitionNumberCannotInventEffortRating() {
        let model = draft(exercises: [exercise("Bench", sets: (0..<3).map { _ in .init(reps: 8, difficulty: 8) })])
        XCTAssertFalse(WorkoutDraftArbiter.choose(
            deterministic: .init(), model: model, sourceText: "Bench 3x8"
        ).hasContent)
        XCTAssertEqual(WorkoutDraftArbiter.choose(
            deterministic: .init(), model: model, sourceText: "Bench 3x8 RPE 8"
        ).totalSetCount, 3)
    }


    func testUnstatedModelWeightUnitUsesPreferenceButLiteralUnitWins() {
        let model = draft(exercises: [exercise("Bench", sets: [.init(weight: 60, weightUnit: .lb, reps: 8)])])
        let inferred = FoundationModelsWorkoutScanParser.applyingSourceWeightUnits(
            to: model, source: "Bench 1x8 at 60", defaultUnit: .kg
        )
        XCTAssertEqual(inferred.exercises[0].sets[0].weightUnit, .kg)
        let explicit = FoundationModelsWorkoutScanParser.applyingSourceWeightUnits(
            to: model, source: "Bench 1x8 at 60lb", defaultUnit: .kg
        )
        XCTAssertEqual(explicit.exercises[0].sets[0].weightUnit, .lb)
    }

}


private actor ParseStageRecorder {
    var stages: [WorkoutParseStage] = []
    func append(_ stage: WorkoutParseStage) { stages.append(stage) }
}
