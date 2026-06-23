import XCTest
@testable import marble

/// Pins the behavior of the deterministic handwritten-notation parser. The parser is
/// pure, so these tests need no model context — they assert the exact structured
/// output for each documented notation.
final class HandwrittenWorkoutParserTests: MarbleTestCase {

    private func parse(_ text: String) -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parse(text, referenceDate: Self.fixedNow)
    }

    private func expectedDate(year: Int, month: Int, day: Int) -> Date {
        Self.stableCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Strength: sets × reps

    func testSimpleSetsByReps() {
        let draft = parse("Squat 5x5")
        XCTAssertEqual(draft.exercises.count, 1)
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Squat")
        XCTAssertEqual(exercise.sets.count, 5)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 5 && $0.weight == nil && $0.durationSeconds == nil && $0.distance == nil })
    }

    func testSetsRepsWithAtWeightAndUnit() {
        let draft = parse("Bench Press 3x5 @ 135 lb")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 5 && $0.weight == 135 && $0.weightUnit == .lb })
    }

    func testTrailingBareNumberIsWeight() {
        let draft = parse("Squat 5x5 225")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 5)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 5 && $0.weight == 225 && $0.weightUnit == .lb })
    }

    func testEmbeddedWeight() {
        let draft = parse("Front Squat 5x5x185")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Front Squat")
        XCTAssertEqual(exercise.sets.count, 5)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 5 && $0.weight == 185 })
    }

    func testKilogramsUnit() {
        let draft = parse("Deadlift 3x3 @ 100 kg")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 3 && $0.weight == 100 && $0.weightUnit == .kg })
    }

    func testSingleWeightByRepsSet() {
        let draft = parse("Deadlift 315x5")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].weight, 315)
        XCTAssertEqual(exercise.sets[0].reps, 5)
    }

    func testWeightRepsPairList() {
        let draft = parse("Bench 135x5 155x3 175x1")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertEqual(exercise.sets.map(\.weight), [135, 155, 175])
        XCTAssertEqual(exercise.sets.map(\.reps), [5, 3, 1])
    }

    func testDecimalWeightWithAt() {
        let draft = parse("Curl 3x10 @ 22.5")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 10 && $0.weight == 22.5 })
    }

    // MARK: - Bodyweight

    func testBodyweightRepsOnly() {
        let draft = parse("Pull ups 3x12")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Pull ups")
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 12 && $0.weight == nil })
        let profile = exercise.metricsProfile
        XCTAssertTrue(profile.usesReps)
        XCTAssertFalse(profile.usesWeight)
        XCTAssertFalse(profile.usesDistance)
        XCTAssertFalse(profile.usesDuration)
    }

    func testLoneRepCount() {
        let draft = parse("Push ups 20")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].reps, 20)
        XCTAssertNil(exercise.sets[0].weight)
    }

    // MARK: - Timed

    func testTimedSetsSeconds() {
        let draft = parse("Plank 3x30s")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.durationSeconds == 30 && $0.reps == nil && $0.weight == nil })
    }

    func testTimedSetsColon() {
        let draft = parse("Plank 3x1:00")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.durationSeconds == 60 })
    }

    // MARK: - Cardio

    func testCardioDistanceAndDuration() {
        let draft = parse("Run 5k 25:00")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Run")
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].distance, 5)
        XCTAssertEqual(exercise.sets[0].distanceUnit, .kilometers)
        XCTAssertEqual(exercise.sets[0].durationSeconds, 25 * 60)
        XCTAssertNil(exercise.sets[0].reps)
    }

    func testCardioDistanceOnly() {
        let draft = parse("Run 5km")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].distance, 5)
        XCTAssertEqual(exercise.sets[0].distanceUnit, .kilometers)
        XCTAssertNil(exercise.sets[0].durationSeconds)
    }

    func testRowMetersDuration() {
        let draft = parse("Row 2000m 7:30")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets[0].distance, 2000)
        XCTAssertEqual(exercise.sets[0].distanceUnit, .meters)
        XCTAssertEqual(exercise.sets[0].durationSeconds, 7 * 60 + 30)
    }

    // MARK: - Dates & titles

    func testSlashDateHeaderSetsDateAndTitle() {
        let draft = parse("1/20 Leg Day")
        XCTAssertEqual(draft.performedAt, expectedDate(year: 2025, month: 1, day: 20))
        XCTAssertEqual(draft.title, "Leg Day")
        XCTAssertTrue(draft.exercises.isEmpty)
    }

    func testISODateHeader() {
        let draft = parse("2025-03-04\nBench 3x5")
        XCTAssertEqual(draft.performedAt, expectedDate(year: 2025, month: 3, day: 4))
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
    }

    // MARK: - Normalization & noise

    func testMultiplySignAndCapitalX() {
        XCTAssertEqual(parse("Squat 5×5").exercises[0].sets.count, 5)
        XCTAssertEqual(parse("Squat 5X5").exercises[0].sets.count, 5)
    }

    func testCommaSeparatedPairs() {
        let draft = parse("Bench 135x5, 155x3")
        XCTAssertEqual(draft.exercises[0].sets.map(\.weight), [135, 155])
    }

    func testNoiseLinesAreIgnored() {
        let draft = parse("Squat 5x5\n----\n???\n   \nBench 3x5")
        XCTAssertEqual(draft.exercises.count, 2)
        XCTAssertEqual(draft.exercises.map(\.name), ["Squat", "Bench"])
    }

    func testEmptyTextHasNoContent() {
        let draft = parse("")
        XCTAssertTrue(draft.exercises.isEmpty)
        XCTAssertFalse(draft.hasContent)
    }

    // MARK: - A realistic page

    func testRealisticMultiLineNote() {
        let note = """
        Push Day 6/22
        Bench Press 3x5 @ 185
        Incline DB Press 3x10 @ 60
        Pull ups 3x12
        Plank 3x45s
        """
        let draft = parse(note)
        XCTAssertEqual(draft.performedAt, expectedDate(year: 2025, month: 6, day: 22))
        XCTAssertEqual(draft.title, "Push Day")
        XCTAssertEqual(draft.exercises.map(\.name), ["Bench Press", "Incline DB Press", "Pull ups", "Plank"])
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
        XCTAssertEqual(draft.exercises[0].sets[0].weight, 185)
        XCTAssertEqual(draft.exercises[3].sets[0].durationSeconds, 45)
        XCTAssertEqual(draft.totalSetCount, 12)
        XCTAssertTrue(draft.hasContent)
    }
}
