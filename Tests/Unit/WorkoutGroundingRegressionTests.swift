import XCTest
@testable import marble

@MainActor
final class WorkoutGroundingRegressionTests: MarbleTestCase {
    private func choose(_ source: String, _ exercises: [ParsedExerciseDraft]) -> ParsedWorkoutDraft {
        WorkoutDraftArbiter.choose(
            deterministic: HandwrittenWorkoutParser.parseDetailed(source, referenceDate: now).draft,
            model: ParsedWorkoutDraft(exercises: exercises), sourceText: source
        )
    }

    func testDictatedDumbbellDecadeLoadStaysWithItsMovement() {
        let source = "bench press four sets of six at one ninety five and then incline dumbbell press three sets of eight with the fifties"
        let result = choose(source, [
            .init(name: "Bench Press", sets: Array(repeating: .init(weight: 195, reps: 6), count: 4)),
            .init(name: "Incline Dumbbell Press", sets: Array(repeating: .init(weight: 50, reps: 8), count: 3))
        ])
        XCTAssertEqual(result.importableExercises.count, 2)
        XCTAssertEqual(result.importableExercises.last?.sets.map(\.weight), [50, 50, 50])
    }

    func testAgeDecadeDoesNotJustifyInventedLoad() {
        let source = "a man in his fifties watched my incline dumbbell press three sets of eight"
        let result = WorkoutDraftArbiter.choose(deterministic: .init(),
            model: .init(exercises: [.init(name: "Incline Dumbbell Press", sets: Array(repeating: .init(weight: 50, reps: 8), count: 3))]),
            sourceText: source)
        XCTAssertFalse(result.hasContent)
    }

    func testDictatedRunAndPlankKeepSeparateDurations() {
        let result = choose("went for a run four miles in thirty six minutes and then did a plank for two minutes", [
            .init(name: "Run", sets: [.init(distance: 4, distanceUnit: .miles, durationSeconds: 2160)]),
            .init(name: "Plank", sets: [.init(durationSeconds: 120)])
        ])
        XCTAssertEqual(result.importableExercises.count, 2)
        XCTAssertEqual(result.importableExercises.first?.sets.first?.durationSeconds, 2160)
        XCTAssertEqual(result.importableExercises.last?.sets.first?.durationSeconds, 120)
    }

    func testOneNamedRampCanReplaceParserFragmentation() {
        let result = choose("Squat worked up: 135 for 10, 155 for 8, 175 for 6", [
            .init(name: "Squat", sets: [.init(weight: 135, reps: 10), .init(weight: 155, reps: 8), .init(weight: 175, reps: 6)])
        ])
        XCTAssertEqual(result.importableExercises.count, 1)
        XCTAssertEqual(result.importableExercises.first?.sets.map(\.reps), [10, 8, 6])
        XCTAssertEqual(result.importableExercises.first?.sets.map(\.weight), [135, 155, 175])
    }
}
