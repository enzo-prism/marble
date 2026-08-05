import XCTest
@testable import marble

/// Pins the paste-compatibility and zero-silent-loss behaviors: app-export set
/// rows (Hevy/Strong), name-less set lines continuing the previous exercise,
/// thousands separators, AMRAP/failure, EMOM, relative dates, name cleanup, the
/// prose guard, dropped-line diagnostics, and the caller-supplied default
/// weight unit.
@MainActor
final class HandwrittenWorkoutParserPasteTests: MarbleTestCase {

    private func parse(_ text: String) -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parse(text, referenceDate: Self.fixedNow)
    }

    private func parseDetailed(
        _ text: String,
        defaultWeightUnit: WeightUnit = .lb
    ) -> WorkoutParseResult {
        HandwrittenWorkoutParser.parseDetailed(
            text,
            referenceDate: Self.fixedNow,
            defaultWeightUnit: defaultWeightUnit
        )
    }

    // MARK: - App-export set rows

    func testHevyExportParsesNameWeightAndReps() {
        let result = parseDetailed("""
        Exercise: Bench Press (Barbell)
        Set 1: 60 kg x 10
        Set 2: 70 kg x 8
        """)
        XCTAssertEqual(result.draft.exercises.count, 1)
        let exercise = result.draft.exercises[0]
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets.count, 2)
        XCTAssertEqual(exercise.sets[0].weight, 60)
        XCTAssertEqual(exercise.sets[0].weightUnit, .kg)
        XCTAssertEqual(exercise.sets[0].reps, 10)
        XCTAssertEqual(exercise.sets[1].weight, 70)
        XCTAssertEqual(exercise.sets[1].reps, 8)
        XCTAssertTrue(result.droppedLines.isEmpty)
        // The header became the exercise, not the title.
        XCTAssertEqual(result.draft.title, "Scanned workout")
    }

    func testStrongExportMultipleExercises() {
        let draft = parse("""
        Squat
        Set 1: 225 lb x 5
        Set 2: 225 lb x 5

        Leg Press
        Set 1: 360 x 10
        """)
        XCTAssertEqual(draft.exercises.map(\.name), ["Squat", "Leg Press"])
        XCTAssertEqual(draft.exercises[0].sets.count, 2)
        XCTAssertEqual(draft.exercises[1].sets.count, 1)
        XCTAssertEqual(draft.exercises[1].sets[0].weight, 360)
        XCTAssertEqual(draft.exercises[1].sets[0].reps, 10)
    }

    func testSetRowWithoutWeightIsBodyweightReps() {
        let draft = parse("""
        Pushups
        Set 1: 12
        Set 2: 10 reps
        """)
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].reps, 12)
        XCTAssertNil(sets[0].weight)
        XCTAssertEqual(sets[1].reps, 10)
    }

    func testSetRowWithoutPrecedingNameIsDropped() {
        let result = parseDetailed("Set 1: 225 lb x 5")
        XCTAssertTrue(result.draft.exercises.isEmpty)
        XCTAssertEqual(result.droppedLines.count, 1)
    }

    func testSetRowCarriesRestWhenWritten() {
        let draft = parse("""
        Bench
        Set 1: 185 x 8 rest 90s
        """)
        XCTAssertEqual(draft.exercises[0].sets[0].restSeconds, 90)
    }

    // MARK: - Name-less continuation lines

    func testNamelessLinesContinuePreviousExercise() {
        let draft = parse("""
        Bench Press
        185 x 8
        185 x 6
        """)
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises[0].sets.map(\.reps), [8, 6])
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 185 })
    }

    func testNamelessLinesAfterNamedExerciseLine() {
        let draft = parse("""
        Bench 185x8
        185x8
        185x6
        """)
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
    }

    func testNamelessLineWithNoExerciseIsDropped() {
        let result = parseDetailed("185 x 8")
        XCTAssertTrue(result.draft.exercises.isEmpty)
        XCTAssertEqual(result.droppedLines, ["185 x 8"])
    }

    func testTitleStillWinsWhenNormalExerciseLinesFollow() {
        let draft = parse("""
        Push Day
        Bench 3x8 @ 185
        """)
        XCTAssertEqual(draft.title, "Push Day")
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench"])
    }

    func testTitleAndPromotedExerciseCoexist() {
        let draft = parse("""
        Push Day
        Bench Press
        185 x 8
        """)
        XCTAssertEqual(draft.title, "Push Day")
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench Press"])
        XCTAssertEqual(draft.exercises[0].sets.count, 1)
    }

    // MARK: - Thousands separators

    func testThousandsSeparatorIsOneLoad() {
        let draft = parse("Squat 3x5 @ 1,025 lb")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 1025 && $0.weightUnit == .lb })
    }

    func testListCommaStillSeparatesPairs() {
        let draft = parse("Bench 135x10, 155x8, 185x6")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
        XCTAssertEqual(draft.exercises[0].sets.map(\.weight), [135, 155, 185])
    }

    // MARK: - AMRAP / failure / EMOM

    func testAmrapKeepsSetCountWithNoReps() {
        let draft = parse("Pushups 3xAMRAP")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == nil && $0.weight == nil })
    }

    func testSpacedFailureNotationParses() {
        let draft = parse("Pull-ups 2x failure")
        XCTAssertEqual(draft.exercises[0].sets.count, 2)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == nil })
    }

    func testEmomExpandsToOneSetPerMinute() {
        let draft = parse("EMOM 10 min: 5 burpees")
        XCTAssertEqual(draft.exercises[0].name, "burpees")
        XCTAssertEqual(draft.exercises[0].sets.count, 10)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == 5 })
    }

    // MARK: - Relative dates

    func testYesterdaySetsDateAndLeavesTheName() {
        let draft = parse("yesterday bench 3x8 @ 185")
        XCTAssertEqual(draft.exercises[0].name, "bench")
        let components = Self.stableCalendar.dateComponents([.year, .month, .day], from: try! XCTUnwrap(draft.performedAt))
        let expected = Self.stableCalendar.dateComponents(
            [.year, .month, .day],
            from: Calendar.current.date(byAdding: .day, value: -1, to: Self.fixedNow)!
        )
        XCTAssertEqual(components.year, expected.year)
        XCTAssertEqual(components.month, expected.month)
        XCTAssertEqual(components.day, expected.day)
    }

    func testRelativeWordWinsOverExplicitDateOnTheSameLine() {
        // "yesterday 7/22" — the relative word is read first, so it keeps the
        // session date; the explicit date is stripped but does not override it.
        let draft = parse("yesterday 7/22\nBench 3x8")
        let performedAt = try! XCTUnwrap(draft.performedAt)
        let expected = Calendar.current.date(byAdding: .day, value: -1, to: Self.fixedNow)!
        let actual = Self.stableCalendar.dateComponents([.year, .month, .day], from: performedAt)
        let wanted = Self.stableCalendar.dateComponents([.year, .month, .day], from: expected)
        XCTAssertEqual(actual.year, wanted.year)
        XCTAssertEqual(actual.month, wanted.month)
        XCTAssertEqual(actual.day, wanted.day)
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench"])
    }

    // MARK: - Name cleanup

    func testEmojiBulletStripsFromName() {
        let draft = parse("💪 Bench 3x8 @ 185")
        XCTAssertEqual(draft.exercises[0].name, "Bench")
    }

    func testUnspacedNameAndSpecSplit() {
        let draft = parse("squat5x5")
        XCTAssertEqual(draft.exercises[0].name, "squat")
        XCTAssertEqual(draft.exercises[0].sets.count, 5)
    }

    func testSupersetTagStillParsesAfterSplitRule() {
        let draft = parse("A1: Bench Press 3x8 @ 185")
        XCTAssertEqual(draft.exercises[0].name, "Bench Press")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
    }

    // MARK: - Prose guard

    func testSpelledOutSetsLineIsNotMangledIntoExercise() {
        let result = parseDetailed("Bench press three sets of eight at 185")
        XCTAssertTrue(result.draft.exercises.isEmpty)
        XCTAssertEqual(result.droppedLines.count, 1)
    }

    func testSetsOfWordPhraseIsProse() {
        let result = parseDetailed("did 4 sets of squats at 225 for 5 reps")
        XCTAssertTrue(result.draft.exercises.isEmpty)
        XCTAssertEqual(result.droppedLines.count, 1)
    }

    // MARK: - Dropped-line diagnostics

    func testUnparseableLinesAreReportedInOrder() {
        let result = parseDetailed("""
        Bench 3x8 @ 185
        round 2 of 3 felt easy
        Squat 5x5
        """)
        XCTAssertEqual(result.draft.exercises.count, 2)
        XCTAssertEqual(result.droppedLines, ["round 2 of 3 felt easy"])
    }

    func testTitleAndRestLinesAreNotDropped() {
        let result = parseDetailed("""
        Push Day
        Bench 3x8 @ 185
        rest 90s
        """)
        XCTAssertTrue(result.droppedLines.isEmpty)
    }

    // MARK: - Default weight unit

    func testDefaultWeightUnitAppliesToUnitlessWeights() {
        let result = parseDetailed("Bench 3x8 @ 100", defaultWeightUnit: .kg)
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weight == 100 && $0.weightUnit == .kg })
    }

    func testExplicitUnitBeatsDefault() {
        let result = parseDetailed("Bench 3x8 @ 100 lb", defaultWeightUnit: .kg)
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .lb })
    }

    func testHistoricDefaultIsPounds() {
        let result = parseDetailed("Bench 3x8 @ 100")
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .lb })
    }
}
