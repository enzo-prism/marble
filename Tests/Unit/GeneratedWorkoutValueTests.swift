import XCTest
@testable import marble

#if canImport(FoundationModels)
@MainActor
final class GeneratedWorkoutValueTests: MarbleTestCase {
    private func generated(weights: [Double]?, reps: [Int]?) -> GeneratedExercise {
        GeneratedExercise(
            name: "Bench", setCount: 3, reps: nil, weight: nil,
            weightUnit: "unknown", restSeconds: nil, durationSeconds: nil,
            distance: nil, distanceUnit: "none", perSetWeights: weights,
            perSetReps: reps
        )
    }

    func testMissingGeneratedMetricsKeepTheirPositions() throws {
        let result = try XCTUnwrap(generated(weights: [100, 0, 120], reps: [8, 0, 6]).draft())
        XCTAssertEqual(result.sets.map(\.weight), [100, nil, 120])
        XCTAssertEqual(result.sets.map(\.reps), [8, nil, 6])
    }

    func testShortGeneratedArraysDoNotInventRepeatedValues() throws {
        let result = try XCTUnwrap(generated(weights: [100, 120], reps: [8]).draft())
        XCTAssertEqual(result.sets.map(\.weight), [100, 120, nil])
        XCTAssertEqual(result.sets.map(\.reps), [8, nil, nil])
    }

    func testUnspecifiedGeneratedUnitUsesUserPreference() throws {
        let result = try XCTUnwrap(generated(weights: [60], reps: [8]).draft(defaultWeightUnit: .kg))
        XCTAssertTrue(result.sets.allSatisfy { $0.weightUnit == .kg })
    }
}
#endif
