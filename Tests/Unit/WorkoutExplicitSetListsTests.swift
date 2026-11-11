import XCTest
@testable import marble

@MainActor
final class WorkoutExplicitSetListsTests: MarbleTestCase {
    private func parse(_ source: String, unit: WeightUnit = .lb) -> WorkoutParseResult {
        HandwrittenWorkoutParser.parseDetailed(source, referenceDate: now, defaultWeightUnit: unit)
    }

    func testParallelListsKeepEachRepAndLoad() {
        for source in ["Shoulder Press 4 sets 12 10 8 8 at 50 55 60 60",
                       "Shoulder Press 4 sets 12, 10, 8, 8 at 50, 55, 60, 60"] {
            let result = parse(source, unit: .kg)
            XCTAssertTrue(result.droppedLines.isEmpty, source)
            XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [12, 10, 8, 8])
            XCTAssertEqual(result.draft.exercises.first?.sets.map(\.weight), [50, 55, 60, 60])
            XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg })
        }
    }

    func testLeadingCountWithRepListAndOneLoad() {
        let result = parse("3 sets 11 9 7 reps on Lat Pulldown at 52.5 kg")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.first?.name, "Lat Pulldown")
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [11, 9, 7])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.weight), [52.5, 52.5, 52.5])
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg })
    }

    func testWorkedUpPairsParallelLists() {
        let result = parse("worked up 135 185 225 for 5 5 3 on Squat")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.first?.name, "Squat")
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.weight), [135, 185, 225])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [5, 5, 3])
    }

    func testFailureListUsesActualCompletedReps() {
        let result = parse("Chin Ups 5 sets to failure: 12, 10, 8, 7, 6")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [12, 10, 8, 7, 6])
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weight == nil })
    }

    func testDropSetPairsStayWithOneMovementIncludingLightLoads() {
        let result = parse("Cable Curls drop set 20x12, 15x10, 10x8 kg")
        XCTAssertTrue(result.droppedLines.isEmpty)
        XCTAssertEqual(result.draft.exercises.map(\.name), ["Cable Curls"])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.reps), [12, 10, 8])
        XCTAssertEqual(result.draft.exercises.first?.sets.map(\.weight), [20, 15, 10])
        XCTAssertTrue(result.draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg })
    }

    func testMismatchedListsStayUnresolved() {
        for source in ["Press 4 sets 12 10 8 at 50 55 60",
                       "Press 3 sets 12 10 8 at 50 55",
                       "3 sets 12 10 reps on Press at 50",
                       "Chin Ups 3 sets to failure: 12, 10, 8, 6",
                       "worked up 135 185 for 5 5 3 on Squat",
                       "Press 3 sets 10 8.5 6 at 50 55 60"] {
            let result = parse(source)
            XCTAssertFalse(result.draft.hasContent, source)
            XCTAssertEqual(result.droppedLines, [source])
        }
    }

    func testWeightFirstTripleAndSetsFirstTripleRemainDistinct() {
        let heavy = parse("Bench 225x5x3")
        XCTAssertEqual(heavy.draft.totalSetCount, 3)
        XCTAssertTrue(heavy.droppedLines.isEmpty)
        XCTAssertFalse(ModelEscalationPolicy.shouldRunModel(for: heavy, sourceText: "Bench 225x5x3", referenceDate: now))
        XCTAssertTrue(heavy.draft.exercises[0].sets.allSatisfy { $0.weight == 225 && $0.reps == 5 })
        let ordinary = parse("Bench 3x5x225")
        XCTAssertEqual(ordinary.draft.totalSetCount, 3)
        XCTAssertTrue(ordinary.draft.exercises[0].sets.allSatisfy { $0.weight == 225 && $0.reps == 5 })
    }
}
