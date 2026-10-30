import XCTest
@testable import marble

/// Independently selected Notes formats. Unsupported wording may remain explicitly
/// unresolved, but must never become a silently different completed workout.
@MainActor
final class WorkoutNotesHeldOutTests: MarbleTestCase {
    private func parse(_ text: String) -> WorkoutParseResult {
        HandwrittenWorkoutParser.parseDetailed(text, referenceDate: Self.fixedNow)
    }

    private func assertExactOrUnresolved(
        _ source: String,
        matches: (ParsedWorkoutDraft) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = parse(source)
        if result.droppedLines.isEmpty {
            XCTAssertTrue(matches(result.draft), "Silent incorrect completion: \(source)", file: file, line: line)
        } else {
            // These single-line cases cannot safely save a partial interpretation.
            XCTAssertFalse(result.draft.hasContent, "Ambiguous source also produced completed sets: \(source)", file: file, line: line)
        }
    }

    private func assertExact(
        _ source: String,
        matches: (ParsedWorkoutDraft) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = parse(source)
        XCTAssertTrue(result.droppedLines.isEmpty, source, file: file, line: line)
        XCTAssertTrue(matches(result.draft), source, file: file, line: line)
    }

    func testNotesNonbreakingSpacesAndWindowsNewlines() {
        let result = parse("• Bounds\u{00A0}(2 sets)\r\n• Sprints — 2 sets, 50 m each")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Bounds", "Sprints"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [2, 2])
        XCTAssertTrue(result.draft.exercises.first?.sets.allSatisfy { !$0.hasAnyValue } == true)
        XCTAssertTrue(result.draft.exercises.last?.sets.allSatisfy {
            $0.distance == 50 && $0.distanceUnit == .meters && $0.reps == nil && $0.weight == nil
        } == true)
    }

    func testCommaRepLadderCannotCollapseToFirstValue() {
        assertExact("Bench 185 lb: 8, 7, 6 reps") { draft in
            draft.exercises.count == 1 && draft.totalSetCount == 3
                && draft.exercises[0].sets.map(\.reps) == [8, 7, 6]
                && draft.exercises[0].sets.allSatisfy { $0.weight == 185 && $0.weightUnit == .lb }
        }
    }

    func testMultilineLoadLadderPreservesPairing() {
        let result = parse("Bench\n135×8\n155×6\n175×4")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Bench"])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.weight), [135, 155, 175])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [8, 6, 4])
    }

    func testLightKilogramLoadsAreNotSetCounts() {
        assertExact("DB curl 20kg x 10, 18kg x 12") { draft in
            draft.totalSetCount == 2 && draft.exercises.count == 1
                && draft.exercises[0].sets.map(\.weight) == [20, 18]
                && draft.exercises[0].sets.map(\.reps) == [10, 12]
                && draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg }
        }
    }

    func testTotalDistanceIsNeverDuplicatedAcrossSets() {
        assertExactOrUnresolved("Sprints: 2 sets, 50m total") { draft in
            draft.exercises.count == 1 && draft.totalSetCount == 2
                && draft.exercises[0].sets.allSatisfy { $0.distance == nil }
                && draft.notes?.contains("50") == true
        }
    }

    func testExplicitEachDistanceAndTotalCannotBeConfused() {
        assertExactOrUnresolved("Sprints: 2 sets, 100m total, 50m each") { draft in
            draft.exercises.count == 1 && draft.totalSetCount == 2
                && draft.exercises[0].sets.allSatisfy {
                    $0.distance == 50 && $0.distanceUnit == .meters && $0.reps == nil
                }
        }
    }

    func testCorrectionDoesNotLogOriginalPrescription() {
        assertExactOrUnresolved("Bench 3x8 @185 — actually only did 2 sets") { draft in
            draft.exercises.count == 1 && draft.totalSetCount == 2
                && draft.exercises[0].sets.allSatisfy { $0.weight == 185 && $0.reps == 8 }
        }
    }

    func testSkippedMovementCannotBecomeCompleted() {
        assertExactOrUnresolved("Skipped squats 3x5. Did lunges 2x10.") { draft in
            draft.totalSetCount == 2 && draft.exercises.count == 1
                && draft.exercises[0].name.lowercased().contains("lunge")
                && !draft.exercises[0].name.lowercased().contains("squat")
                && draft.exercises[0].sets.allSatisfy { $0.reps == 10 }
        }
    }

    func testPlannedWorkWithoutCompletedActivityStaysUnresolved() {
        let source = "Tomorrow: squat 3x5"
        let result = parse(source)
        XCTAssertFalse(result.draft.hasContent)
        XCTAssertEqual(result.droppedLines, [source])
    }

    func testInlineCircuitDoesNotLoseSecondMovement() {
        assertExact("3 rounds: 10 pushups + 15 squats") { draft in
            draft.exercises.count == 2 && draft.exercises.map { $0.sets.count } == [3, 3]
                && draft.exercises[0].sets.allSatisfy { $0.reps == 10 }
                && draft.exercises[1].sets.allSatisfy { $0.reps == 15 }
        }
    }

    func testSupersetLabelsNeverBecomeExerciseMetrics() {
        for source in ["A1 Bench 3x8 @135", "A2 Row 3x10 @95"] {
            let isBench = source.contains("Bench")
            assertExact(source) { draft in
                draft.exercises.count == 1 && draft.totalSetCount == 3
                    && draft.exercises[0].name == (isBench ? "Bench" : "Row")
                    && draft.exercises[0].sets.allSatisfy {
                        $0.reps == (isBench ? 8 : 10) && $0.weight == (isBench ? 135 : 95)
                    }
            }
        }
    }

    func testRepeatedMovementBlocksKeepTheirOrderAndLoad() {
        let result = parse("Squat 2x5 @100kg\nBench 2x8 @60kg\nSquat 1x3 @110kg")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Squat", "Bench", "Squat"])
        XCTAssertEqual(result.draft.exercises.map { $0.sets.count }, [2, 2, 1])
        XCTAssertEqual(result.draft.exercises.flatMap(\.sets).map(\.weight), [100, 100, 60, 60, 110])
        XCTAssertEqual(result.draft.exercises.flatMap(\.sets).map(\.reps), [5, 5, 8, 8, 3])
    }

    func testBodyweightAndSleepNumbersDoNotBecomeDrillMetrics() {
        assertExactOrUnresolved("Bounds 2 sets. Felt about 80% today; 90kg bodyweight, slept 7h.") { draft in
            draft.exercises.count == 1 && draft.totalSetCount == 2
                && draft.exercises[0].name == "Bounds"
                && draft.exercises[0].sets.allSatisfy { !$0.hasAnyValue && $0.difficulty == nil }
                && draft.notes?.contains("slept") == true
        }
    }

    func testLongNotesDoNotTruncateTrailingClearWorkout() {
        let notes = String(repeating: "Recovery note: legs felt heavy but movement was comfortable.\n", count: 100)
        let result = parse("Bench 2x8 @185\n" + notes + "Sprints 2x50m")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Bench", "Sprints"])
        XCTAssertEqual(result.draft.totalSetCount, 4)
        XCTAssertTrue(result.draft.exercises.first?.sets.allSatisfy { $0.weight == 185 && $0.reps == 8 } == true)
        XCTAssertTrue(result.draft.exercises.last?.sets.allSatisfy { $0.distance == 50 && $0.reps == nil } == true)
        XCTAssertTrue(result.draft.notes?.contains("Recovery note") == true)
    }
}
