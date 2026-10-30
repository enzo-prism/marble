import XCTest
@testable import marble

@MainActor
final class HandwrittenWorkoutParserCountedNotesTests: MarbleTestCase {
    private func parse(_ text: String) -> WorkoutParseResult {
        HandwrittenWorkoutParser.parseDetailed(text, referenceDate: Self.fixedNow)
    }

    func testOwnerAppleNotesWorkoutPreservesAllEightEfforts() {
        let result = parse("""
            9/4/26

            Straight Leg Speed Bounds (2 sets)

            Knee Drive Speed Bounds (2 sets)

            Resistance Rope Sprint 2 sets , 50m each

            Sprints , 2 sets , 50m each
            """)
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.title, "Scanned workout")
        XCTAssertEqual(result.draft.exercises.map(\.name), [
            "Straight Leg Speed Bounds", "Knee Drive Speed Bounds", "Resistance Rope Sprint", "Sprints"
        ])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [2, 2, 2, 2])
        XCTAssertEqual(result.draft.totalSetCount, 8)
        XCTAssertEqual(result.draft.performedAt.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) },
                       DateComponents(year: 2026, month: 9, day: 4))
        for exercise in result.draft.exercises.prefix(2) {
            XCTAssertTrue(exercise.sets.allSatisfy { !$0.hasAnyValue })
        }
        for exercise in result.draft.exercises.suffix(2) {
            XCTAssertTrue(exercise.sets.allSatisfy {
                $0.distance == 50 && $0.distanceUnit == .meters && $0.reps == nil && $0.weight == nil && $0.durationSeconds == nil
            })
        }
        XCTAssertEqual(Set(result.draft.exercises.flatMap(\.sets).map(\.id)).count, 8)
    }

    func testCountOnlyFormatCorpusDoesNotInventReps() {
        for input in ["Bounds (2 sets)", "Bounds(2sets)", "• Bounds: 2 sets", "Bounds — two sets",
                      "Bounds [2 sets]", "Bounds 2sets", "2 sets of Bounds", "two sets of Bounds"] {
            let result = parse(input)
            XCTAssertTrue(result.droppedLines.isEmpty, input)
            XCTAssertEqual(result.draft.exercises.first?.name, "Bounds", input)
            XCTAssertEqual(result.draft.totalSetCount, 2, input)
            XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy { !$0.hasAnyValue }, input)
        }
    }

    func testDistanceCountFormatCorpus() {
        for input in ["Sprints 2 sets, 50m each", "Sprints (two sets), 50 meters each", "Sprints 2sets 50m",
                      "• Sprints: 2 sets of 50 m", "two sets of 50 meters Sprints", "Sprints 2 sets — 50-meter each"] {
            let result = parse(input)
            XCTAssertTrue(result.droppedLines.isEmpty, input)
            XCTAssertEqual(result.draft.exercises.first?.name, "Sprints", input)
            XCTAssertEqual(result.draft.totalSetCount, 2, input)
            XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy { $0.distance == 50 && $0.reps == nil }, input)
        }
    }

    func testExplicitRepsAreNotMistakenForLoad() {
        for input in ["Pushups 2 sets of 30 reps", "Pushups two sets of 30", "two sets of 30 reps Pushups"] {
            let result = parse(input)
            XCTAssertTrue(result.droppedLines.isEmpty, input)
            XCTAssertEqual(result.draft.totalSetCount, 2, input)
            XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy { $0.reps == 30 && $0.weight == nil }, input)
        }
    }

    func testTimedAndLoadedCounts() {
        let timed = parse("Plank three sets of 45 seconds each")
        XCTAssertEqual(timed.draft.totalSetCount, 3)
        XCTAssertTrue(timed.draft.exercises.flatMap(\.sets).allSatisfy { $0.durationSeconds == 45 && $0.reps == nil })
        let loaded = parse("Bench Press three sets of eight at 185 lb")
        XCTAssertEqual(loaded.draft.totalSetCount, 3)
        XCTAssertTrue(loaded.draft.exercises.flatMap(\.sets).allSatisfy { $0.reps == 8 && $0.weight == 185 })
    }

    func testCountOnlyContinuationPromotesExerciseHeader() {
        let result = parse("Bounds\n2 sets")
        XCTAssertEqual(result.draft.exercises.first?.name, "Bounds")
        XCTAssertEqual(result.draft.totalSetCount, 2)
        XCTAssertTrue(result.droppedLines.isEmpty)
    }

    func testCountedEffortsRespectCircuitMultiplier() {
        let result = parse("3 rounds:\nBounds 2 sets")
        XCTAssertEqual(result.draft.totalSetCount, 6)
        XCTAssertEqual(Set(result.draft.exercises.flatMap(\.sets).map(\.id)).count, 6)
    }

    func testInvalidOrConflictingCountsRemainUnresolved() {
        for input in ["Bounds 0 sets", "Bounds -2 sets", "Bounds 2.5 sets", "Bounds 101 sets",
                      "Bounds 999999999999999999999 sets", "Bounds 2 sets or 3 sets", "Sprints 2 sets 3x50m",
                      "Sprints 2 sets 50m total", "planned 2 sets of Bounds",
                      "Bounds actually 3 sets not 2", "Sprints 2 sets 50m 75m"] {
            let result = parse(input)
            XCTAssertFalse(result.draft.hasContent, input)
            XCTAssertEqual(result.droppedLines, [input], input)
        }
    }

    func testRepRangeRetainsWrittenIntentAlongsideLowerBound() {
        let result = parse("Curls 3x8-12 @25lb")
        XCTAssertEqual(result.draft.totalSetCount, 3)
        XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy {
            $0.reps == 8 && $0.notes == "Rep range written: 8-12"
        })
    }

    func testCommaSeparatedRepLaddersPreserveEverySet() {
        for source in ["Bench 185 lb: 8, 7, 6 reps", "Bench185lb:8,7,6reps"] {
            let result = parse(source)
            XCTAssertTrue(result.droppedLines.isEmpty, source)
            XCTAssertEqual(result.draft.exercises.map(\.name), ["Bench"], source)
            XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [8, 7, 6], source)
            XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy { $0.weight == 185 && $0.weightUnit == .lb }, source)
        }
    }

    func testSupersetLabelsAreOnlyOrderingLabels() {
        let result = parse("A1 Bench 3x8 @135\nA2: Row 3x10 @95")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Bench", "Row"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [3, 3])
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.reps == 8 && $0.weight == 135 })
        XCTAssertTrue(result.draft.exercises[1].sets.allSatisfy { $0.reps == 10 && $0.weight == 95 })
    }

    func testInlineCircuitHasEveryMovementInOrder() {
        for source in ["3 rounds: 10 pushups + 15 squats", "3 rounds:10pushups +15squats",
                       "three rounds: Pushups 10 + Squats 15"] {
            let result = parse(source)
            XCTAssertTrue(result.droppedLines.isEmpty, source)
            XCTAssertEqual(result.draft.exercises.map { $0.name.lowercased() }, ["pushups", "squats"], source)
            XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [3, 3], source)
            XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.reps == 10 && $0.weight == nil }, source)
            XCTAssertTrue(result.draft.exercises[1].sets.allSatisfy { $0.reps == 15 && $0.weight == nil }, source)
            XCTAssertEqual(Set(result.draft.exercises.flatMap(\.sets).map(\.id)).count, 6, source)
        }
    }

    func testInlineCircuitAmbiguityCannotPartiallyLog() {
        for source in ["3 rounds: 10 pushups + unknown", "100 rounds:10pushups+15squats",
                       "3 rounds: 50 m sprints + 10 pushups", "3 rounds: 10 pushups +"] {
            let result = parse(source)
            XCTAssertFalse(result.draft.hasContent, source)
            XCTAssertEqual(result.droppedLines, [source], source)
        }
    }

    func testRunThenRepeatedPlanksPreservesBothActivities() {
        let result = parse("Yesterday I ran 5 kilometers in 25 minutes, then did three planks of 45 seconds each.")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map { $0.name.lowercased() }, ["run", "planks"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [1, 3])
        XCTAssertEqual(result.draft.exercises[0].sets[0].distance, 5)
        XCTAssertEqual(result.draft.exercises[0].sets[0].distanceUnit, .kilometers)
        XCTAssertEqual(result.draft.exercises[0].sets[0].durationSeconds, 1500)
        XCTAssertTrue(result.draft.exercises[1].sets.allSatisfy { $0.durationSeconds == 45 && $0.distance == nil && $0.reps == nil })
        XCTAssertEqual(result.draft.performedAt, Calendar.current.date(byAdding: .day, value: -1, to: Self.fixedNow))
    }

    func testTransitionsAreCompleteOrEntirelyUnresolved() {
        let clear = parse("Bounds 2 sets then Sprints 50m")
        XCTAssertTrue(clear.droppedLines.isEmpty)
        XCTAssertEqual(clear.draft.exercises.map(\.name), ["Bounds", "Sprints"])
        for source in ["Run 5km then something else", "Run 5km and three planks",
                       "Run 5km. Did three planks."] {
            let result = parse(source)
            XCTAssertFalse(result.draft.hasContent, source)
            XCTAssertEqual(result.droppedLines, [source], source)
        }
    }

    func testTrailingSentencePunctuationDoesNotLoseCountedWorkout() {
        let result = parse("9/4/26\nBench press:135x5,155x3,175x1\nSquat: two sets of five at 100kg.")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map { $0.name.lowercased() }, ["bench press", "squat"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [3, 2])
        XCTAssertTrue(result.draft.exercises[1].sets.allSatisfy { $0.reps == 5 && $0.weight == 100 && $0.weightUnit == .kg })
    }

    func testNaturalLanguageBoundsWorkoutPreservesEveryEffort() {
        let result = parse("Yesterday I did two sets of straight leg speed bounds and two sets of knee drive speed bounds. Then two sets of resistance rope sprints, fifty meters each, followed by two fifty-meter sprints.")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map { $0.name.lowercased() }, ["straight leg speed bounds", "knee drive speed bounds", "resistance rope sprints", "sprints"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [2, 2, 2, 2])
        XCTAssertTrue(result.draft.exercises.prefix(2).flatMap(\.sets).allSatisfy { !$0.hasAnyValue })
        XCTAssertTrue(result.draft.exercises.suffix(2).flatMap(\.sets).allSatisfy { $0.distance == 50 && $0.distanceUnit == .meters && $0.reps == nil })
    }

    func testSpokenLoadsAreCompleteNumbers() {
        let cases: [(String, Double)] = [("one eighty five", 185), ("one hundred eighty five", 185),
            ("one hundred and eighty five", 185), ("two twenty five", 225), ("twenty five", 25)]
        for (spoken, load) in cases {
            let result = parse("three sets of eight on bench at \(spoken)")
            XCTAssertTrue(result.droppedLines.isEmpty, spoken)
            XCTAssertEqual(result.draft.totalSetCount, 3, spoken)
            XCTAssertEqual(result.draft.exercises.first?.name, "bench", spoken)
            XCTAssertTrue(result.draft.exercises.flatMap(\.sets).allSatisfy { $0.weight == load && $0.reps == 8 }, spoken)
        }
    }

    func testUnknownSpokenCompoundCannotBecomeItsFirstWord() {
        for source in ["Bench 3x8 at one eighty five six", "Bench 3x8 at one thousand five",
                       "three sets of eight on bench at twenty five six"] {
            let result = parse(source)
            XCTAssertFalse(result.draft.hasContent, source)
            XCTAssertEqual(result.droppedLines, [source], source)
        }
    }

    func testRestAndBodyweightDescriptionsNeverBecomeExerciseNames() {
        let pullups = parse("Last night I did four sets of six pullups, resting two minutes between sets.")
        XCTAssertTrue(pullups.droppedLines.isEmpty)
        XCTAssertEqual(pullups.draft.exercises.map(\.name), ["pullups"])
        XCTAssertEqual(pullups.draft.totalSetCount, 4)
        XCTAssertTrue(pullups.draft.exercises.flatMap(\.sets).allSatisfy { $0.reps == 6 && $0.restSeconds == 120 })
        let mixed = parse("I did 6 hill sprints of 30 meters each and 2 sets of calf raises, 15 reps each, no added weight.")
        XCTAssertTrue(mixed.droppedLines.isEmpty)
        XCTAssertEqual(mixed.draft.exercises.map(\.name), ["hill sprints", "calf raises"])
        XCTAssertEqual(mixed.draft.exercises.map { $0.sets.count }, [6, 2])
        XCTAssertTrue(mixed.draft.exercises[1].sets.allSatisfy { $0.reps == 15 && $0.weight == nil && $0.notes == "No added weight" })
    }

    func testRoundHeadersApplyToEverySupportedMovementFormat() {
        for (body, expected) in [("2 50m sprints", 6), ("two planks of 30s each", 6),
                                 ("Bench185lb:8,7,6reps", 9), ("Bounds 2 sets then Sprints 50m", 9),
                                 ("EMOM 2 min: 5 burpees", 6), ("Bounds\n2 sets", 6)] {
            let result = parse("3 rounds:\n" + body)
            XCTAssertTrue(result.droppedLines.isEmpty, body)
            XCTAssertEqual(result.draft.totalSetCount, expected, body)
            XCTAssertEqual(Set(result.draft.exercises.flatMap(\.sets).map(\.id)).count, expected, body)
        }
    }

    func testUnsafeExpansionAndNumbersRemainUnresolvedWithoutTrapping() {
        for header in ["9223372036854775807 rounds:", "999999999999999999999 rounds:", "101 rounds:", "0 rounds:", "-2 rounds:", "2.5 rounds:"] {
            let result = parse(header + "\nBounds 2 sets")
            XCTAssertFalse(result.draft.hasContent, header)
            XCTAssertTrue(result.droppedLines.contains(header), header)
        }
        for source in ["EMOM 9223372036854775807 min: 5 burpees", "EMOM 101 min: 5 burpees",
                       "Bench 1x5 rest 999999999999999999999", "Bench 1x5 rest 1e300",
                       "Bench 1x999999999999999999999", "Run 1km 999999999999999999999s",
                       "Bench 1x5 @Infinity", "3 rounds:\nBounds 100 sets"] {
            let result = parse(source)
            XCTAssertFalse(result.draft.hasContent, source)
            XCTAssertFalse(result.droppedLines.isEmpty, source)
        }
    }

    func testExistingShorthandStillMeansTheSameWorkout() {
        XCTAssertEqual(parse("Sprints 2x50m").draft.totalSetCount, 2)
        let bench = parse("Bench 185x8")
        XCTAssertEqual(bench.draft.totalSetCount, 1)
        XCTAssertEqual(bench.draft.exercises.first?.sets.first?.weight, 185)
        XCTAssertEqual(bench.draft.exercises.first?.sets.first?.reps, 8)
        XCTAssertEqual(parse("Pushups 20").draft.exercises.first?.sets.first?.reps, 20)
    }
}
