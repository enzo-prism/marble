import XCTest
@testable import marble

/// Pins the arbiter's choice between the deterministic notation parse and the
/// on-device model parse: empty-draft fast paths, score-based selection, the
/// deterministic tie-break, cross-draft date/title/notes/RPE merging, model
/// provenance, and the set-count extraction the scoring leans on. The later
/// sections pin fixes for probe-verified misjudgments: prose set counts after
/// notation, invented set counts and exercises, article numbers, repeated-set
/// dilution, weight units, and digit-grouping commas.
@MainActor
final class WorkoutDraftArbiterTests: MarbleTestCase {

    // MARK: - Draft builders

    private func draft(
        title: String = "Push day",
        performedAt: Date? = nil,
        notes: String? = nil,
        exercises: [ParsedExerciseDraft]
    ) -> ParsedWorkoutDraft {
        ParsedWorkoutDraft(performedAt: performedAt, notes: notes, title: title, exercises: exercises)
    }

    private func exercise(_ name: String, sets: [ParsedSetDraft]) -> ParsedExerciseDraft {
        ParsedExerciseDraft(name: name, sets: sets)
    }

    private func set(
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        difficulty: Int? = nil
    ) -> ParsedSetDraft {
        ParsedSetDraft(weight: weight, weightUnit: unit, reps: reps, difficulty: difficulty)
    }

    private func benchSets(
        count: Int,
        weight: Double = 185,
        unit: WeightUnit = .lb,
        reps: Int = 8
    ) -> [ParsedSetDraft] {
        (0..<count).map { _ in set(weight: weight, unit: unit, reps: reps) }
    }

    private func score(
        _ draft: ParsedWorkoutDraft,
        _ text: String,
        unit: WeightUnit = .lb
    ) -> Double {
        WorkoutDraftArbiter.score(draft, against: text, defaultWeightUnit: unit)
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


    func testExpectedSetCountHandlesUppercaseX() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3X8"), 3)
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3 X 8"), 3)
    }

    func testExpectedSetCountIncludesSpelledOutSets() {
        let text = "Push day\nBench 3x8 @ 185\nThen incline dumbbell press, three sets of ten with the 60s"
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: text), 6)
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Squats 5 sets of 5 at 225"), 5)
    }

    func testExpectedSetCountDoesNotDoubleCountOneLine() {
        // The same three sets written two ways on one line are still three sets.
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3x8 @ 185, 3 sets"), 3)
    }

    // MARK: - Mixed notation and prose

    func testCorrectModelWinsWhenProseFollowsNotation() {
        // The deterministic parser reads the notation line and drops the prose
        // line; the model reads both. Its prose sets must count as evidence, not
        // as a set-count mismatch against the lone 3x8.
        let text = "Push day\nBench 3x8 @ 185\nThen incline dumbbell press, three sets of ten with the 60s"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [
            exercise("Bench Press", sets: benchSets(count: 3)),
            exercise("Incline Dumbbell Press", sets: benchSets(count: 3, weight: 60, reps: 10))
        ])
        XCTAssertGreaterThan(score(model, text), score(deterministic, text))
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
        XCTAssertEqual(chosen.interpretedByModel, true)
    }

    func testCorrectModelWinsOnCloseGripProseLine() {
        let text = "Bench 3x8 @ 185\nthen close grip bench, three sets of ten at 135"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [
            exercise("Bench Press", sets: benchSets(count: 3)),
            exercise("Close-Grip Bench Press", sets: benchSets(count: 3, weight: 135, reps: 10))
        ])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
    }

    // MARK: - Hallucinations

    func testInventedSetCountCannotExplainHeaderNumber() {
        // "Week 3" is not a set count; three copies of the one written set must
        // not beat the faithful single set by "covering" the 3.
        let text = "Week 3 Day 2\nBench 185 for 8"
        let faithful = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 1))])
        let padded = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        XCTAssertGreaterThan(score(faithful, text), score(padded, text))
        // Padded first, so only the score (not tie order) can pick the faithful draft.
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []), candidates: [padded, faithful], sourceText: text
        )
        XCTAssertEqual(chosen.totalSetCount, 1)
    }

    func testRepeatedSetsBackedByWrittenCountAreNotPenalized() {
        // Each set written out, or the count in set position, backs the repeats.
        let written = "Bench 185x8, 185x8, 185x8"
        let threeSets = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let oneSet = draft(exercises: [exercise("Bench", sets: benchSets(count: 1))])
        XCTAssertEqual(score(threeSets, written), score(oneSet, written), accuracy: 0.0001)
        // Written once, the same three copies are padding.
        XCTAssertLessThan(score(threeSets, "Bench 185x8"), score(oneSet, "Bench 185x8"))
        let emom = "EMOM 10 min: 5 pullups"
        let tenSets = draft(exercises: [exercise("pullups", sets: (0..<10).map { _ in set(reps: 5) })])
        let single = draft(exercises: [exercise("pullups", sets: [set(reps: 5)])])
        XCTAssertGreaterThan(score(tenSets, emom), score(single, emom))
    }

    func testInventedExerciseLowersScore() {
        // "shoulders felt tight" is an aside, not a Shoulder Press set.
        let text = "Bench three sets of 8 at 185, shoulders felt tight"
        let faithful = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        let invented = draft(exercises: [
            exercise("Bench Press", sets: benchSets(count: 3)),
            exercise("Shoulder Press", sets: benchSets(count: 3))
        ])
        XCTAssertGreaterThan(score(faithful, text), score(invented, text))
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []), candidates: [invented, faithful], sourceText: text
        )
        XCTAssertEqual(chosen.exercises, faithful.exercises)
    }

    func testAbbreviatedAndExpandedNamesScoreTheSame() {
        let text = "DB press 3x10 @ 60\nRDL 3x8 @ 185\nOHP 3x5 @ 95\nKB swings 3x15 @ 35"
        let verbatim = draft(exercises: [
            exercise("DB press", sets: benchSets(count: 3, weight: 60, reps: 10)),
            exercise("RDL", sets: benchSets(count: 3, weight: 185, reps: 8)),
            exercise("OHP", sets: benchSets(count: 3, weight: 95, reps: 5)),
            exercise("KB swings", sets: benchSets(count: 3, weight: 35, reps: 15))
        ])
        let expanded = draft(exercises: [
            exercise("Dumbbell Press", sets: benchSets(count: 3, weight: 60, reps: 10)),
            exercise("Romanian Deadlift", sets: benchSets(count: 3, weight: 185, reps: 8)),
            exercise("Overhead Press", sets: benchSets(count: 3, weight: 95, reps: 5)),
            exercise("Kettlebell Swing", sets: benchSets(count: 3, weight: 35, reps: 15))
        ])
        XCTAssertEqual(score(expanded, text), score(verbatim, text), accuracy: 0.0001)
    }

    func testPluralsEquipmentWordsAndOCRSlipsStayGrounded() {
        let text = "Squats 5x5 @ 225\npullups 3x10\nBnech 3x8 @ 185"
        let verbatim = draft(exercises: [
            exercise("Squats", sets: benchSets(count: 5, weight: 225, reps: 5)),
            exercise("pullups", sets: (0..<3).map { _ in set(reps: 10) }),
            exercise("Bnech", sets: benchSets(count: 3))
        ])
        let canonical = draft(exercises: [
            exercise("Barbell Back Squat", sets: benchSets(count: 5, weight: 225, reps: 5)),
            exercise("Pull-Up", sets: (0..<3).map { _ in set(reps: 10) }),
            exercise("Bench Press", sets: benchSets(count: 3))
        ])
        XCTAssertEqual(score(canonical, text), score(verbatim, text), accuracy: 0.0001)
    }

    func testArticleNumberCountsAsOne() {
        // "a mile" states a distance of 1; the draft that records it must not be
        // scored as inventing a number, nor lose to one that skips the distance.
        let text = "Ran a mile in 8 minutes then 3 sets of 20 pushups"
        let pushups = exercise("Pushups", sets: (0..<3).map { _ in set(reps: 20) })
        let withDistance = draft(exercises: [
            exercise("Run", sets: [ParsedSetDraft(distance: 1, distanceUnit: .miles, durationSeconds: 480)]),
            pushups
        ])
        let withoutDistance = draft(exercises: [
            exercise("Run", sets: [ParsedSetDraft(durationSeconds: 480)]),
            pushups
        ])
        XCTAssertGreaterThan(score(withDistance, text), score(withoutDistance, text))
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []), candidates: [withoutDistance, withDistance], sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].sets[0].distance, 1)
    }

    func testArticleWithoutUnitWordStatesNoNumber() {
        // "a bit" is not a 1 the draft must explain.
        let text = "Bench 3x8 @ 185, felt a bit tight"
        let faithful = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        XCTAssertEqual(score(faithful, text), score(faithful, "Bench 3x8 @ 185"), accuracy: 0.0001)
    }

    func testRepeatingACorrectSetDoesNotDiluteAnInventedValue() {
        // Values count once per exercise: five copies of a correct set must not
        // outweigh the invented 999 any more than one copy does.
        let text = "Bench 185x8, 185x8, 185x8, 185x8, 185x8\nSquat 225x5"
        let invented = exercise("Squat", sets: [set(weight: 999, reps: 5)])
        let fiveCopies = draft(exercises: [exercise("Bench", sets: benchSets(count: 5)), invented])
        let oneCopy = draft(exercises: [exercise("Bench", sets: benchSets(count: 1)), invented])
        XCTAssertEqual(score(fiveCopies, text), score(oneCopy, text), accuracy: 0.0001)
        let faithful = draft(exercises: [
            exercise("Bench", sets: benchSets(count: 5)),
            exercise("Squat", sets: [set(weight: 225, reps: 5)])
        ])
        XCTAssertGreaterThan(score(faithful, text), score(fiveCopies, text))
    }

    // MARK: - Weight units

    func testDefaultWeightUnitDecidesUnitlessLoads() {
        let text = "Squats five sets of five at 100, then lunges"
        let inPounds = draft(exercises: [exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .lb, reps: 5))])
        let inKilos = draft(exercises: [exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .kg, reps: 5))])
        XCTAssertGreaterThan(score(inKilos, text, unit: .kg), score(inPounds, text, unit: .kg))
        XCTAssertGreaterThan(score(inPounds, text, unit: .lb), score(inKilos, text, unit: .lb))
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []),
            candidates: [inPounds, inKilos],
            sourceText: text,
            defaultWeightUnit: .kg
        )
        XCTAssertEqual(chosen.exercises[0].sets[0].weightUnit, .kg)
    }

    func testWrittenUnitOutranksDefaultUnit() {
        // "100kg" is written; a pounds user's default must not override it.
        let text = "Squat 5x5 100kg"
        let deterministic = draft(exercises: [exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .lb, reps: 5))])
        let model = draft(exercises: [exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .kg, reps: 5))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text, defaultWeightUnit: .lb
        )
        XCTAssertEqual(chosen.exercises[0].sets[0].weightUnit, .kg)
        XCTAssertEqual(chosen.interpretedByModel, true)
    }

    func testNoteWideUnitAppliesToUnmarkedLoads() {
        // The note only ever says kg, so the unmarked 80 is kg too.
        let text = "Squat 5x5 @ 100kg\nBench 3x8 @ 80"
        func candidate(_ benchUnit: WeightUnit) -> ParsedWorkoutDraft {
            draft(exercises: [
                exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .kg, reps: 5)),
                exercise("Bench", sets: benchSets(count: 3, weight: 80, unit: benchUnit, reps: 8))
            ])
        }
        XCTAssertGreaterThan(score(candidate(.kg), text, unit: .lb), score(candidate(.lb), text, unit: .lb))
    }

    // MARK: - Number tokens

    func testThousandsSeparatorReadsAsOneNumber() {
        let text = "Leg press 3x10 @ 1,025"
        let thousands = draft(exercises: [exercise("Leg Press", sets: benchSets(count: 3, weight: 1025, reps: 10))])
        let split = draft(exercises: [exercise("Leg Press", sets: benchSets(count: 3, weight: 25, reps: 10))])
        XCTAssertGreaterThan(score(thousands, text), score(split, text))
    }

    func testCommaListOfLoadsStaysSeparateNumbers() {
        let text = "Bench 185,205 for 5"
        let twoSets = draft(exercises: [exercise("Bench", sets: [set(weight: 185, reps: 5), set(weight: 205, reps: 5)])])
        let merged = draft(exercises: [exercise("Bench", sets: [set(weight: 185_205, reps: 5)])])
        XCTAssertGreaterThan(score(twoSets, text), score(merged, text))
    }

    // MARK: - Notes and RPE merging

    func testWinnerInheritsLosersNotes() {
        let text = "Bench 185x8\nFelt strong today\nthen curls three sets of twelve at 30"
        let deterministic = draft(
            notes: "Felt strong today",
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let model = draft(exercises: [
            exercise("Bench Press", sets: benchSets(count: 1)),
            exercise("Curl", sets: benchSets(count: 3, weight: 30, reps: 12))
        ])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
        XCTAssertEqual(chosen.notes, "Felt strong today")
    }

    func testWinnerKeepsItsOwnNotes() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(notes: "Mine", exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(notes: "Theirs", exercises: [exercise("Bench", sets: benchSets(count: 1))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.notes, "Mine")
    }

    func testWinnerInheritsLosersRPEForTheSameSet() {
        // The RPE must be written: a model effort rating absent from the text
        // is invented and rejects that exercise instead.
        let text = "Bench 3x8 @ 185 RPE 9"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [
            exercise("Bench Press", sets: [set(weight: 185, reps: 8, difficulty: 9)])
        ])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].name, "Bench")
        XCTAssertEqual(chosen.exercises[0].sets.map(\.difficulty), [9, nil, nil])
    }

    func testRPEIsNotCarriedAcrossDifferentExercises() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [
            exercise("Squat", sets: [set(weight: 185, reps: 8, difficulty: 9)])
        ])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].sets.map(\.difficulty), [nil, nil, nil])
    }

    func testRPEDoesNotOverwriteWinnersOwnRPE() {
        let text = "Bench 3x8 @ 185"
        var winnerSets = benchSets(count: 3)
        winnerSets[0].difficulty = 7
        let deterministic = draft(exercises: [exercise("Bench", sets: winnerSets)])
        let model = draft(exercises: [
            exercise("Bench", sets: [set(weight: 185, reps: 8, difficulty: 9)])
        ])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].sets[0].difficulty, 7)
    }

    // MARK: - Provenance

    func testDeterministicWinLeavesProvenanceUnset() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [exercise("Bench", sets: benchSets(count: 1))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertNil(chosen.interpretedByModel)
    }

    func testIdenticalModelDraftDoesNotClaimProvenance() {
        // Tie → deterministic, even when the model's draft is value-identical.
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: deterministic, sourceText: text
        )
        XCTAssertNil(chosen.interpretedByModel)
    }

    func testModelWinOverEmptyDeterministicSetsProvenance() {
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []),
            model: draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))]),
            sourceText: "three sets of eight on bench at 185"
        )
        XCTAssertEqual(chosen.interpretedByModel, true)
    }

    func testDraftEncodedWithoutProvenanceStillDecodes() throws {
        let legacy = #"{"title":"Push day","exercises":[]}"#
        let decoded = try JSONDecoder().decode(ParsedWorkoutDraft.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.title, "Push day")
        XCTAssertNil(decoded.interpretedByModel)
    }

    // MARK: - Clean-notation regressions

    func testCleanNotationStillPicksDeterministic() {
        // Clean gym shorthand: a renamed-but-equal model draft ties (deterministic
        // keeps priority) and a collapsed one loses — across units and layouts.
        let cases: [(text: String, exercises: [ParsedExerciseDraft])] = [
            ("Bench 3x8 @ 185\nSquat 5x5 @ 225", [
                exercise("Bench", sets: benchSets(count: 3)),
                exercise("Squat", sets: benchSets(count: 5, weight: 225, reps: 5))
            ]),
            ("Squat 5X5 100kg", [
                exercise("Squat", sets: benchSets(count: 5, weight: 100, unit: .kg, reps: 5))
            ]),
            ("Curls 3×12 with 25s", [
                exercise("Curls", sets: benchSets(count: 3, weight: 25, reps: 12))
            ]),
            ("Deadlift 405x1, felt heavy", [
                exercise("Deadlift", sets: [set(weight: 405, reps: 1)])
            ])
        ]
        for testCase in cases {
            let deterministic = draft(exercises: testCase.exercises)
            var renamed = deterministic
            for index in renamed.exercises.indices {
                renamed.exercises[index].name = "Barbell " + renamed.exercises[index].name
            }
            var collapsed = deterministic
            for index in collapsed.exercises.indices {
                collapsed.exercises[index].sets = [collapsed.exercises[index].sets[0]]
            }
            XCTAssertEqual(score(renamed, testCase.text), score(deterministic, testCase.text), accuracy: 0.0001, testCase.text)
            XCTAssertGreaterThanOrEqual(score(deterministic, testCase.text), score(collapsed, testCase.text), testCase.text)
            let chosen = WorkoutDraftArbiter.choose(
                deterministic: deterministic, candidates: [renamed, collapsed], sourceText: testCase.text
            )
            XCTAssertEqual(chosen.exercises, deterministic.exercises, testCase.text)
            XCTAssertNil(chosen.interpretedByModel, testCase.text)
        }
    }
    func testUnitlessSourceGroundsWinningWeightedDipsInUserDefault() {
        let text = "overhead press four sets of six at fifty then dips three sets of ten plus twenty"
        let model = draft(exercises: [
            exercise("Overhead Press", sets: benchSets(count: 4, weight: 50, unit: .kg, reps: 6)),
            exercise("Dips", sets: benchSets(count: 3, weight: 20, unit: .lb, reps: 10))
        ])
        for unit in [WeightUnit.kg, .lb] {
            let chosen = WorkoutDraftArbiter.choose(
                deterministic: draft(exercises: []), model: model, sourceText: text, defaultWeightUnit: unit
            )
            XCTAssertEqual(chosen.exercises.count, 2)
            XCTAssertEqual(chosen.exercises[0].sets.map(\.weight), [50, 50, 50, 50])
            XCTAssertEqual(chosen.exercises[1].sets.map(\.weight), [20, 20, 20])
            XCTAssertEqual(chosen.exercises[0].sets.map(\.reps), [6, 6, 6, 6])
            XCTAssertEqual(chosen.exercises[1].sets.map(\.reps), [10, 10, 10])
            XCTAssertTrue(chosen.exercises.flatMap(\.sets).allSatisfy { $0.weightUnit == unit })
        }
    }

    func testExplicitUnitVariantsInhibitDefaultOverride() {
        for spelling in ["lb", "lbs", "pound", "pounds", "LB", "#"] {
            let model = draft(exercises: [exercise("Dips", sets: benchSets(count: 3, weight: 20, unit: .lb, reps: 10))])
            let chosen = WorkoutDraftArbiter.choose(
                deterministic: draft(exercises: []), model: model,
                sourceText: "Dips 3x10 @ 20" + spelling, defaultWeightUnit: .kg
            )
            XCTAssertEqual(chosen.exercises[0].sets[0].weightUnit, .lb, spelling)
            XCTAssertEqual(chosen.exercises[0].sets[0].weight, 20, spelling)
        }
        for spelling in ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "KG"] {
            let model = draft(exercises: [exercise("Dips", sets: benchSets(count: 3, weight: 20, unit: .kg, reps: 10))])
            let chosen = WorkoutDraftArbiter.choose(
                deterministic: draft(exercises: []), model: model,
                sourceText: "Dips three sets of ten at twenty " + spelling, defaultWeightUnit: .lb
            )
            XCTAssertEqual(chosen.exercises[0].sets[0].weightUnit, .kg, spelling)
        }
    }

    func testMixedUnitsAndPoundsHeaderArePreserved() {
        let model = draft(exercises: [
            exercise("Bench", sets: benchSets(count: 3, weight: 80, unit: .kg, reps: 8)),
            exercise("Dips", sets: benchSets(count: 3, weight: 20, unit: .lb, reps: 10))
        ])
        let mixed = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []), model: model,
            sourceText: "Bench 3x8 @ 80kg; Dips 3x10 @ 20lbs", defaultWeightUnit: .kg
        )
        XCTAssertEqual(mixed.exercises[0].sets[0].weightUnit, .kg)
        XCTAssertEqual(mixed.exercises[1].sets[0].weightUnit, .lb)
        let header = WorkoutDraftArbiter.choose(
            deterministic: draft(exercises: []), model: model,
            sourceText: "All weights #\nBench 3x8 @ 80\nDips 3x10 @ 20", defaultWeightUnit: .kg
        )
        XCTAssertEqual(header.exercises[1].sets[0].weightUnit, .lb)
    }

    func testCompactUnitBeforeMultiplicationIsExplicit() {
        for (text, unit, defaultUnit, load) in [
            ("Bench 80kgx8", WeightUnit.kg, WeightUnit.lb, 80.0),
            ("Bench 80KGX8", .kg, .lb, 80.0),
            ("Bench 80kg×8", .kg, .lb, 80.0),
            ("Bench 225lbsx5", .lb, .kg, 225.0),
            ("Bench 225pounds×5", .lb, .kg, 225.0)
        ] {
            let model = draft(exercises: [exercise("Bench", sets: benchSets(count: 1, weight: load, unit: unit, reps: 8))])
            let chosen = WorkoutDraftArbiter.choose(
                deterministic: draft(exercises: []), model: model, sourceText: text, defaultWeightUnit: defaultUnit
            )
            XCTAssertEqual(chosen.exercises[0].sets[0].weightUnit, unit, text)
            XCTAssertEqual(chosen.exercises[0].sets[0].weight, load, text)
        }
    }

}


private actor ParseStageRecorder {
    var stages: [WorkoutParseStage] = []
    func append(_ stage: WorkoutParseStage) { stages.append(stage) }
}
