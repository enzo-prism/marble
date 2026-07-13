import SwiftData
import XCTest
@testable import marble

@MainActor
final class SprintPrescriptionTests: MarbleTestCase {
    func testExactTargetBoundaries() {
        let plan = SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 19
        )

        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.targetMode, .time)
        XCTAssertEqual(plan.outcome(for: 18), .metTime)
        XCTAssertEqual(plan.outcome(for: 19), .metTime)
        XCTAssertEqual(plan.outcome(for: 20), .missedTime)
        XCTAssertEqual(plan.targetText(), "19s or faster")
    }

    func testRangeTargetIsInclusive() {
        let plan = SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )

        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.targetMode, .range)
        XCTAssertEqual(plan.outcome(for: 18), .fasterThanRange)
        XCTAssertEqual(plan.outcome(for: 19), .inRange)
        XCTAssertEqual(plan.outcome(for: 21), .inRange)
        XCTAssertEqual(plan.outcome(for: 22), .slowerThanRange)
        XCTAssertEqual(plan.targetText(), "19–21s")
    }

    func testInvalidPrescriptionValues() {
        XCTAssertFalse(SprintPrescriptionPlan(distance: 0, repetitionCount: 4, targetLowerSeconds: 19, targetUpperSeconds: 21).isValid)
        XCTAssertFalse(SprintPrescriptionPlan(distance: 150, repetitionCount: 0, targetLowerSeconds: 19, targetUpperSeconds: 21).isValid)
        XCTAssertFalse(SprintPrescriptionPlan(distance: 150, repetitionCount: 4, targetLowerSeconds: 0, targetUpperSeconds: 21).isValid)
        XCTAssertFalse(SprintPrescriptionPlan(distance: 150, repetitionCount: 4, targetLowerSeconds: 21, targetUpperSeconds: 19).isValid)
    }

    func testPrescriptionPersistsAndFetchesByExercise() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "150m Sprints",
            category: .power,
            preferredDistanceUnit: .meters,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 180
        )
        let prescription = SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )
        context.insert(exercise)
        context.insert(prescription)
        try context.save()

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SprintPrescription>()).first)
        XCTAssertEqual(restored.exerciseID, exercise.id)
        XCTAssertEqual(restored.plan, SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        XCTAssertEqual(restored.summary(distanceUnit: .meters, restSeconds: 180), "4 × 150 m · target 19–21s · 3m rest")
    }

    func testOrphanCleanupRemovesPrescriptionAfterExerciseDeletion() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let prescription = SprintPrescription(
            exerciseID: exercise.id,
            distance: 60,
            repetitionCount: 4,
            targetLowerSeconds: 8,
            targetUpperSeconds: 8
        )
        context.insert(exercise)
        context.insert(prescription)
        try context.save()
        context.delete(exercise)
        try context.save()

        SprintPrescription.removeOrphans(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
    }
}
