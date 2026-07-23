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

    func testExactGoalEvaluationExplainsHitsAndMisses() {
        let plan = SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 19
        )

        let faster = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 150,
            actualDistanceUnit: .meters,
            actualSeconds: 18
        )
        XCTAssertEqual(faster.status, .hit)
        XCTAssertEqual(faster.outcome, .metTime)
        XCTAssertEqual(faster.actualText, "18s")
        XCTAssertEqual(faster.targetText, "19s or faster")
        XCTAssertEqual(faster.reason, "18s was 1 second faster than your 19s-or-faster goal.")

        let missed = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 150,
            actualDistanceUnit: .meters,
            actualSeconds: 20
        )
        XCTAssertEqual(missed.status, .missed)
        XCTAssertEqual(missed.outcome, .missedTime)
        XCTAssertEqual(missed.reason, "20s was 1 second slower than your 19s-or-faster goal.")
    }

    func testRangeGoalEvaluationTreatsBoundsAsHitsAndExplainsBothMissDirections() {
        let plan = SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )

        for seconds in [19, 20, 21] {
            let result = SprintGoalEvaluation.evaluate(
                plan: plan,
                prescribedDistanceUnit: .meters,
                actualDistance: 150,
                actualDistanceUnit: .meters,
                actualSeconds: seconds
            )
            XCTAssertEqual(result.status, .hit)
            XCTAssertEqual(result.outcome, .inRange)
            XCTAssertEqual(result.reason, "\(seconds)s was inside your target range of 19–21s.")
        }

        let tooFast = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 150,
            actualDistanceUnit: .meters,
            actualSeconds: 18
        )
        XCTAssertEqual(tooFast.status, .missed)
        XCTAssertEqual(tooFast.outcome, .fasterThanRange)
        XCTAssertEqual(tooFast.reason, "18s was 1 second faster than the 19s lower limit.")

        let tooSlow = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 150,
            actualDistanceUnit: .meters,
            actualSeconds: 25
        )
        XCTAssertEqual(tooSlow.status, .missed)
        XCTAssertEqual(tooSlow.outcome, .slowerThanRange)
        XCTAssertEqual(tooSlow.reason, "25s was 4 seconds slower than the 21s upper limit.")
    }

    func testGoalEvaluationRequiresDistanceAndTimeAndUnderstandsEquivalentUnits() {
        let plan = SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )

        let equivalentDistance = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 0.15,
            actualDistanceUnit: .kilometers,
            actualSeconds: 20
        )
        XCTAssertEqual(equivalentDistance.status, .hit)

        let wrongDistance = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 100,
            actualDistanceUnit: .meters,
            actualSeconds: 20
        )
        XCTAssertEqual(wrongDistance.status, .notScored)
        XCTAssertNil(wrongDistance.outcome)
        XCTAssertEqual(wrongDistance.reason, "This rep was 100 m, not the prescribed 150 m.")

        let missingTime = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: 150,
            actualDistanceUnit: .meters,
            actualSeconds: nil
        )
        XCTAssertEqual(missingTime.status, .notScored)
        XCTAssertEqual(missingTime.reason, "Add a sprint time to see whether this rep hit the goal.")

        let missingDistance = SprintGoalEvaluation.evaluate(
            plan: plan,
            prescribedDistanceUnit: .meters,
            actualDistance: nil,
            actualDistanceUnit: .meters,
            actualSeconds: 20
        )
        XCTAssertEqual(missingDistance.status, .notScored)
        XCTAssertEqual(missingDistance.reason, "Add the sprint distance to score this rep.")
    }

    func testSnapshotKeepsOriginalGoalAfterPrescriptionChanges() {
        let exerciseID = UUID()
        let entryID = UUID()
        let prescription = SprintPrescription(
            exerciseID: exerciseID,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )
        let snapshot = SprintGoalSnapshot(
            setEntryID: entryID,
            exerciseID: exerciseID,
            distance: prescription.distance,
            distanceUnit: .meters,
            repetitionNumber: 2,
            repetitionCount: prescription.repetitionCount,
            targetLowerSeconds: prescription.targetLowerSeconds,
            targetUpperSeconds: prescription.targetUpperSeconds
        )

        prescription.distance = 200
        prescription.repetitionCount = 6
        prescription.targetLowerSeconds = 22
        prescription.targetUpperSeconds = 24

        XCTAssertEqual(snapshot.plan, SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        XCTAssertEqual(snapshot.distanceUnit, .meters)
        XCTAssertEqual(snapshot.repetitionNumber, 2)
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

    func testSprintGoalSnapshotPersistsAndOrphanCleanupRemovesItAfterSetDeletion() throws {
        let schema = Schema(versionedSchema: MarbleSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MarbleMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let exercise = Exercise(
            name: "150m Sprint",
            category: .run,
            preferredDistanceUnit: .meters,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 180
        )
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        )
        let snapshot = SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 2,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )
        context.insert(exercise)
        context.insert(entry)
        context.insert(snapshot)
        try context.save()

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SprintGoalSnapshot>()).first)
        XCTAssertEqual(restored.setEntryID, entry.id)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(SprintGoalEvaluation.evaluate(snapshot: restored, entry: entry).status, .hit)

        context.delete(entry)
        try context.save()
        SprintGoalSnapshot.removeOrphans(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }

    func testLegacySprintGoalBackfillIsInferredAndIdempotent() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "150m Sprint",
            category: .run,
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
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 25,
            restAfterSeconds: 180
        )
        context.insert(exercise)
        context.insert(prescription)
        context.insert(entry)
        try context.save()

        XCTAssertEqual(SprintGoalSnapshot.backfillLegacyEntries(in: context), 1)
        try context.save()
        XCTAssertEqual(SprintGoalSnapshot.backfillLegacyEntries(in: context), 0)

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SprintGoalSnapshot>()).first)
        XCTAssertTrue(restored.isInferred)
        XCTAssertNil(restored.repetitionNumber)
        XCTAssertEqual(restored.targetLowerSeconds, 19)
        XCTAssertEqual(restored.targetUpperSeconds, 21)
        XCTAssertEqual(SprintGoalEvaluation.evaluate(snapshot: restored, entry: entry).status, .missed)
    }

    /// The orphan sweep now compares key columns via `propertiesToFetch`
    /// instead of materializing both tables; this pins the mixed case — it
    /// must delete *only* the orphan, never a still-linked prescription.
    func testOrphanCleanupPreservesLinkedPrescriptionsInMixedTable() throws {
        let context = makeInMemoryContext()
        let kept = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let deleted = Exercise(name: "Hill Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let keptPrescription = SprintPrescription(
            exerciseID: kept.id,
            distance: 60,
            repetitionCount: 4,
            targetLowerSeconds: 8,
            targetUpperSeconds: 8
        )
        let orphanedPrescription = SprintPrescription(
            exerciseID: deleted.id,
            distance: 100,
            repetitionCount: 3,
            targetLowerSeconds: 14,
            targetUpperSeconds: 16
        )
        context.insert(kept)
        context.insert(deleted)
        context.insert(keptPrescription)
        context.insert(orphanedPrescription)
        try context.save()
        context.delete(deleted)
        try context.save()

        SprintPrescription.removeOrphans(in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SprintPrescription>())
        XCTAssertEqual(remaining.map(\.exerciseID), [kept.id])
    }

    /// The backfill's eligibility guards moved into a store predicate (entries
    /// need a distance, a duration, and a prescribed exercise), so pin each
    /// skip reason the loop used to enforce in memory: missing duration, an
    /// unprescribed exercise, and an invalid prescription.
    func testLegacySprintGoalBackfillSkipsIneligibleEntries() throws {
        let context = makeInMemoryContext()
        let sprint = Exercise(
            name: "150m Sprint",
            category: .run,
            preferredDistanceUnit: .meters,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 180
        )
        let unprescribed = Exercise(
            name: "Tempo Run",
            category: .run,
            preferredDistanceUnit: .kilometers,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 0
        )
        let badlyPrescribed = Exercise(
            name: "Broken Sprint",
            category: .run,
            preferredDistanceUnit: .meters,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 180
        )
        let prescription = SprintPrescription(
            exerciseID: sprint.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )
        // Invalid on purpose (zero target): entries for this exercise are
        // predicate candidates but must still be rejected by `isValid`.
        let invalidPrescription = SprintPrescription(
            exerciseID: badlyPrescribed.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 0,
            targetUpperSeconds: 0
        )
        let eligible = SetEntry(
            exercise: sprint,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        )
        let missingDuration = SetEntry(
            exercise: sprint,
            performedAt: now.addingTimeInterval(-60),
            distance: 150,
            restAfterSeconds: 180
        )
        let noPrescription = SetEntry(
            exercise: unprescribed,
            performedAt: now.addingTimeInterval(-120),
            distance: 3,
            durationSeconds: 900,
            restAfterSeconds: 0
        )
        let invalidGoal = SetEntry(
            exercise: badlyPrescribed,
            performedAt: now.addingTimeInterval(-180),
            distance: 150,
            durationSeconds: 22,
            restAfterSeconds: 180
        )
        [sprint, unprescribed, badlyPrescribed].forEach(context.insert)
        [prescription, invalidPrescription].forEach(context.insert)
        [eligible, missingDuration, noPrescription, invalidGoal].forEach(context.insert)
        try context.save()

        XCTAssertEqual(SprintGoalSnapshot.backfillLegacyEntries(in: context), 1)
        try context.save()

        let snapshots = try context.fetch(FetchDescriptor<SprintGoalSnapshot>())
        XCTAssertEqual(snapshots.map(\.setEntryID), [eligible.id])
    }
}
