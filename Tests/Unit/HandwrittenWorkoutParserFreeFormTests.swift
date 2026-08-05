import XCTest
@testable import marble

/// Pins the free-form notation behaviors added for real-world typed/dictated notes:
/// en/em dashes, hyphenated units ("20-meter", "20-pound"), word weight units,
/// intensity percentages as noise, rep ranges, distance B-values, and spec-first
/// lines where the exercise name follows the numbers.
@MainActor
final class HandwrittenWorkoutParserFreeFormTests: MarbleTestCase {

    private func parse(_ text: String) -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parse(text, referenceDate: Self.fixedNow)
    }

    // MARK: - Dash normalization

    func testEnDashRepRangeParsesAsHyphen() {
        let draft = parse("Calf raises 4x8–10")
        XCTAssertEqual(draft.exercises.count, 1)
        XCTAssertEqual(draft.exercises[0].sets.count, 4)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == 8 })
    }

    func testEmDashRepRangeParsesAsHyphen() {
        let draft = parse("Calf raises 4x8—10")
        XCTAssertEqual(draft.exercises[0].sets.count, 4)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == 8 })
    }

    func testHyphenatedUnitAttachesToNumber() {
        let draft = parse("Flyes 2x15 with 20-pound dumbbells")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 15 && $0.weight == 20 && $0.weightUnit == .lb })
    }

    func testHyphenBetweenWordsSurvivesInNames() {
        let draft = parse("Rear-delt flyes 2x15")
        XCTAssertEqual(draft.exercises[0].name, "Rear-delt flyes")
    }

    func testISODateStillDetectedAfterDashNormalization() {
        let draft = parse("2025-03-04\nBench 3x5")
        XCTAssertEqual(
            draft.performedAt,
            Self.stableCalendar.date(from: DateComponents(year: 2025, month: 3, day: 4, hour: 12))
        )
        XCTAssertEqual(draft.exercises.count, 1)
    }

    // MARK: - Word weight units

    func testPoundsWordIsWeightUnit() {
        let draft = parse("Bench 3x5 @ 185 pounds")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 185 && $0.weightUnit == .lb })
    }

    func testPoundSingularIsWeightUnit() {
        let draft = parse("Curls 2x10 with 25 pound dumbbells")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 25 && $0.weightUnit == .lb })
    }

    func testKilogramWordsAreKgUnit() {
        let draft = parse("Deadlift 3x3 @ 100 kilograms")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 100 && $0.weightUnit == .kg })
    }

    func testKilosWordIsKgUnit() {
        let draft = parse("Press 3x5 60 kilos")
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weight == 60 && $0.weightUnit == .kg })
    }

    // MARK: - Intensity percentages

    func testPercentTokenIsNeverAWeight() {
        let draft = parse("Squat 5x5 at 85%")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 5)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 && $0.weight == nil })
    }

    func testPercentRangeTokenIsNoise() {
        let draft = parse("Accelerations 3x30m at 85-90%")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.weight == nil && $0.reps == nil && $0.distance == 30 })
    }

    // MARK: - Rep ranges

    func testRepRangeBValueUsesLowerBound() {
        let draft = parse("Calf raises 4x8-10")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 8 && $0.weight == nil })
    }

    func testBareRepRangeIsOneSetOfLowerBound() {
        let draft = parse("Curls 8-10")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].reps, 8)
        XCTAssertNil(sets[0].weight)
    }

    func testTrailingRangeAfterAxBDoesNotCorrupt() {
        let draft = parse("Squat 3x5 8-10")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 && $0.weight == nil })
    }

    // MARK: - Distance B-values

    func testDistanceBValueShortUnit() {
        let draft = parse("Sprints 4x20m")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(sets.allSatisfy {
            $0.distance == 20 && $0.distanceUnit == .meters && $0.reps == nil && $0.durationSeconds == nil
        })
    }

    func testDistanceBValueWordUnit() {
        let draft = parse("Accelerations 3x30meter")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.distance == 30 && $0.distanceUnit == .meters })
    }

    // MARK: - Leading-spec lines

    func testLeadingSpecLineNameAfterNumbers() {
        let draft = parse("4x20meter accelerations at 85-90%")
        XCTAssertEqual(draft.exercises.count, 1)
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "accelerations")
        XCTAssertEqual(exercise.sets.count, 4)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.distance == 20 && $0.distanceUnit == .meters })
    }

    func testLeadingSpecLineWithFillerWordsAndWeight() {
        let draft = parse("3x10 goblet squats with a 50 pound dumbbell")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "goblet squats")
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 10 && $0.weight == 50 && $0.weightUnit == .lb })
    }

    func testLeadingSpecLineWithoutAnyNameIsDropped() {
        let draft = parse("5x5")
        XCTAssertTrue(draft.exercises.isEmpty)
    }

    func testNameFirstLinesAreUnchangedByFallback() {
        let draft = parse("Squat 5x5")
        XCTAssertEqual(draft.exercises[0].name, "Squat")
        XCTAssertEqual(draft.exercises[0].sets.count, 5)
    }

    // MARK: - "each leg" / "each side" noise

    func testEachLegAfterSpecIsIgnored() {
        let draft = parse("Split squats 3x5 each leg")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 })
    }

    func testEachSideAfterSpecIsIgnored() {
        let draft = parse("Lunges 3x8 each side")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == 8 })
    }

    // MARK: - Rep ladders / pyramids

    func testWeightPrefixedSlashLadder() {
        let draft = parse("Bench 225x5/3/1")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Bench")
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertEqual(exercise.sets.map(\.reps), [5, 3, 1])
        XCTAssertTrue(exercise.sets.allSatisfy { $0.weight == 225 && $0.weightUnit == .lb })
    }

    func testBareSlashLadderTakesAtWeight() {
        let draft = parse("Squat 5/3/1 @ 225")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.sets.count, 3)
        XCTAssertEqual(exercise.sets.map(\.reps), [5, 3, 1])
        XCTAssertTrue(exercise.sets.allSatisfy { $0.weight == 225 })
        XCTAssertNil(draft.performedAt, "A 3-segment rep ladder is not a partial M/D date")
    }

    func testDashLadderWithLeadingCount() {
        let draft = parse("Bench 3x10-8-6")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.reps), [10, 8, 6])
        XCTAssertTrue(sets.allSatisfy { $0.weight == nil })
    }

    func testLeadingCountDisagreementPrefersRungs() {
        // "1x" claims one set but the ladder lists three rungs — the rungs are
        // the actual data, so they win.
        let draft = parse("Deadlift 1x5/3/1 @ 405")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.reps), [5, 3, 1])
        XCTAssertTrue(sets.allSatisfy { $0.weight == 405 })
    }

    func testTwoSegmentSlashStaysADate() {
        // Ladders need 3+ rungs; "6/22" remains a date header.
        let draft = parse("6/22 Bench 3x8")
        XCTAssertNotNil(draft.performedAt)
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
    }

    func testFullSlashDateStillDetectedWithLadderGuard() {
        let draft = parse("6/22/25 Bench 3x8")
        let components = Self.stableCalendar.dateComponents(
            [.year, .month, .day],
            from: try! XCTUnwrap(draft.performedAt)
        )
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 22)
        XCTAssertEqual(draft.exercises.count, 1)
    }

    // MARK: - Tempo notation

    func testTempoKeywordPairIsNoise() {
        // Without stripping, "31x1" reads as a second weight×reps pair and the
        // sets come out as "3 lb x 5" and "31 lb x 1".
        let draft = parse("Squat 3x5 tempo 31x1")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 && $0.weight == nil })
    }

    func testTempoDashPatternAfterKeyword() {
        let draft = parse("Bench 3x8 @ 185 tempo 3-0-1")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 8 && $0.weight == 185 })
    }

    func testParenthesizedTempoIsNoise() {
        let draft = parse("Squat 3x5 @ 225 (31X1)")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 && $0.weight == 225 })
    }

    func testFourSegmentTempo() {
        let draft = parse("Squat 3x5 tempo 4-1-2-0")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 && $0.weight == nil })
    }

    func testBareWeightRepsPairsAreNotTempo() {
        // Conservative stripping: no keyword, no parentheses → the pairs stay.
        let draft = parse("Bench 135x5 155x3")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.map(\.weight), [135, 155])
        XCTAssertEqual(sets.map(\.reps), [5, 3])
    }

    // MARK: - "N by M" notation

    func testByBetweenNumbersReadsAsX() {
        let draft = parse("Overhead press 5 by 5 at 95 pounds")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Overhead press")
        XCTAssertEqual(exercise.sets.count, 5)
        XCTAssertTrue(exercise.sets.allSatisfy { $0.reps == 5 && $0.weight == 95 && $0.weightUnit == .lb })
    }

    func testByInsideNameStaysHarmless() {
        let draft = parse("Pull by cable 3x10")
        XCTAssertEqual(draft.exercises[0].name, "Pull by cable")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.reps == 10 })
    }

    // MARK: - Rep words (single / double / triple)

    func testDoubleAfterBareWeightAndFillerName() {
        let draft = parse("worked up to 225 on bench for a double")
        XCTAssertEqual(draft.exercises.count, 1)
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "bench")
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].weight, 225)
        XCTAssertEqual(exercise.sets[0].reps, 2)
    }

    func testSingleRepWord() {
        let draft = parse("Deadlift 315 for a single")
        let exercise = draft.exercises[0]
        XCTAssertEqual(exercise.name, "Deadlift")
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].weight, 315)
        XCTAssertEqual(exercise.sets[0].reps, 1)
    }

    func testTripleRepWord() {
        let draft = parse("Squat 405 for a triple")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].weight, 405)
        XCTAssertEqual(sets[0].reps, 3)
    }

    // MARK: - Name-filler stripping

    func testLeadingDidIsStrippedFromName() {
        let draft = parse("did pull ups 4x10")
        XCTAssertEqual(draft.exercises[0].name, "pull ups")
        XCTAssertEqual(draft.exercises[0].sets.count, 4)
    }

    func testInnerFillerWordsSurviveInNames() {
        let draft = parse("Warm up 3x10")
        XCTAssertEqual(draft.exercises[0].name, "Warm up")
        XCTAssertEqual(draft.exercises[0].sets.count, 3)
    }

    // MARK: - Lone bare-number disambiguation

    func testLoneLargeBareNumberIsWeight() {
        let draft = parse("Bench 225")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].weight, 225)
        XCTAssertNil(sets[0].reps)
    }

    func testLoneSmallBareNumberStaysReps() {
        let draft = parse("Pushups 20")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].reps, 20)
        XCTAssertNil(sets[0].weight)
    }

    func testLoneBareNumberAtThresholdIsWeight() {
        let draft = parse("Bench 25")
        let sets = draft.exercises[0].sets
        XCTAssertEqual(sets[0].weight, 25)
        XCTAssertNil(sets[0].reps)
    }

    // MARK: - The full pole-vault note

    func testFullPoleVaultFreeFormNote() {
        let note = """
        4 × 20-meter accelerations at 85–90%
        3 × 30-meter accelerations at 85–90%
        Split squats: 3 × 5 each leg
        Calf raises: 4 × 8–10
        Pull-ups: 1 × 10
        Rear-delt dumbbell flyes: 2 × 15 with 20-pound dumbbells
        Swinging Bubka high-bar drill: 2 × 5
        """
        let draft = parse(note)

        XCTAssertNil(draft.performedAt)
        XCTAssertEqual(draft.title, "Scanned workout", "No word-only line exists, so the default title stands")
        XCTAssertEqual(draft.exercises.count, 7)
        XCTAssertEqual(draft.exercises.map(\.name), [
            "accelerations",
            "accelerations",
            "Split squats",
            "Calf raises",
            "Pull-ups",
            "Rear-delt dumbbell flyes",
            "Swinging Bubka high-bar drill"
        ])

        // Two acceleration blocks stay separate, in order.
        let first = draft.exercises[0]
        XCTAssertEqual(first.sets.count, 4)
        XCTAssertTrue(first.sets.allSatisfy {
            $0.distance == 20 && $0.distanceUnit == .meters && $0.reps == nil && $0.weight == nil
        })
        let second = draft.exercises[1]
        XCTAssertEqual(second.sets.count, 3)
        XCTAssertTrue(second.sets.allSatisfy { $0.distance == 30 && $0.distanceUnit == .meters })

        let splitSquats = draft.exercises[2]
        XCTAssertEqual(splitSquats.sets.count, 3)
        XCTAssertTrue(splitSquats.sets.allSatisfy { $0.reps == 5 })

        let calfRaises = draft.exercises[3]
        XCTAssertEqual(calfRaises.sets.count, 4)
        XCTAssertTrue(calfRaises.sets.allSatisfy { $0.reps == 8 })

        let pullUps = draft.exercises[4]
        XCTAssertEqual(pullUps.sets.count, 1)
        XCTAssertEqual(pullUps.sets[0].reps, 10)

        let flyes = draft.exercises[5]
        XCTAssertEqual(flyes.sets.count, 2)
        XCTAssertTrue(flyes.sets.allSatisfy { $0.reps == 15 && $0.weight == 20 && $0.weightUnit == .lb })

        let bubka = draft.exercises[6]
        XCTAssertEqual(bubka.sets.count, 2)
        XCTAssertTrue(bubka.sets.allSatisfy { $0.reps == 5 && $0.weight == nil })
    }
}
