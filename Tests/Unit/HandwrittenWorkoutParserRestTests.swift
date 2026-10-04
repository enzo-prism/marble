import XCTest
@testable import marble

/// Pins the rest-notation behavior of the deterministic parser: inline "rest"
/// tokens, value-first "90s rest", bare-number heuristics, and rest-only
/// continuation lines that apply to the previous exercise.
@MainActor
final class HandwrittenWorkoutParserRestTests: MarbleTestCase {

    private func parse(_ text: String) -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parse(text, referenceDate: Self.fixedNow)
    }

    func testRestAfterMarkerWithUnit() {
        let draft = parse("Bench Press 3x8 @ 185 rest 90s")
        XCTAssertEqual(draft.exercises.count, 1)
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 90 && $0.reps == 8 && $0.weight == 185 })
    }

    func testRestBeforeMarker() {
        let draft = parse("Squat 5x5 225 90s rest")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 5)
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 90 && $0.weight == 225 })
    }

    func testBareNumberAfterRestIsSecondsWhenLarge() {
        let draft = parse("Bench 3x8 rest 90")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 90 })
    }

    func testBareNumberAfterRestIsMinutesWhenSmall() {
        let draft = parse("Deadlift 5x3 rest 3")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 180 })
    }

    func testRestWithMinutesUnit() {
        let draft = parse("Squat 5x5 rest 2min")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 120 })
    }

    func testRestOnlyLineAppliesToPreviousExercise() {
        let draft = parse("Bench Press 3x8 @ 185\nrest 90s")
        XCTAssertEqual(draft.exercises.count, 1, "A rest-only line must not become an exercise")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 90 })
    }

    func testRestOnlyLineWithTrailingWords() {
        let draft = parse("Squat 5x5\n2 min rest between sets")
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 120 })
    }

    func testRestDoesNotBecomeTimedSet() {
        let draft = parse("Bench 3x8 90s rest")
        let sets = draft.exercises[0].sets
        XCTAssertTrue(sets.allSatisfy { $0.durationSeconds == nil })
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 90 })
    }

    func testTimedSetWithRestKeepsBothApart() {
        let draft = parse("Plank 3x45s rest 30s")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.durationSeconds == 45 && $0.restSeconds == 30 })
    }

    func testLinesWithoutRestAreUnchanged() {
        let draft = parse("Squat 5x5 @ 225")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == nil })
    }

    func testRestOnlyFirstLineIsIgnoredSafely() {
        let draft = parse("rest 90s\nSquat 5x5")
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises[0].name, "Squat")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == nil })
    }
    func testRestPunctuationAndMinuteShorthandPreserveWork() {
        for (suffix, seconds) in [("(rest 90s)", 90), ("(2 min rest)", 120),
                                  ("rest: 45s", 45), ("rest 2m", 120), ("rest 1.5m", 90),
                                  ("rest .5min", 30), ("rest .5m", 30), ("rest .5", 30)] {
            let draft = parse("Bench Press 3x8 @ 185 " + suffix)
            XCTAssertEqual(draft.exercises.count, 1, suffix)
            let sets = draft.exercises.first?.sets ?? []
            XCTAssertEqual(sets.count, 3, suffix)
            XCTAssertTrue(sets.allSatisfy {
                $0.restSeconds == seconds && $0.reps == 8 && $0.weight == 185
                    && $0.durationSeconds == nil && $0.distance == nil
            }, suffix)
        }
    }

    func testWrappedRestContinuationPreservesExplicitRest() {
        let draft = parse("Bench 3x8 rest 60s\n(rest: 2m)")
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises.first?.sets.count, 3)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.restSeconds == 60 })
    }

    func testMetersRemainDistanceOutsideRest() {
        let draft = parse("Run 400m rest 2m")
        XCTAssertEqual(draft.exercises.count, 1)
        let set = draft.exercises.first?.sets.first
        XCTAssertEqual(set?.distance, 400)
        XCTAssertEqual(set?.distanceUnit, .meters)
        XCTAssertEqual(set?.restSeconds, 120)
        XCTAssertNil(set?.durationSeconds)
    }

    func testOversizedSetCountsStayAvailableForReview() {
        for input in ["Plank 999999999x30s", "Bench 999999999x8x100", "EMOM 999999999 min: 5 burpees"] {
            let result = HandwrittenWorkoutParser.parseDetailed(input, referenceDate: Self.fixedNow)
            XCTAssertLessThanOrEqual(result.draft.totalSetCount, 1000, input)
            XCTAssertFalse(result.droppedLines.isEmpty, input)
        }
        let circuit = HandwrittenWorkoutParser.parseDetailed("999999999 rounds:\nPushups 10", referenceDate: Self.fixedNow)
        XCTAssertLessThanOrEqual(circuit.draft.totalSetCount, 1000)
        XCTAssertFalse(circuit.droppedLines.isEmpty)
    }

}
