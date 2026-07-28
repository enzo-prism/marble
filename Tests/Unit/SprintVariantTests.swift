import Foundation
import SwiftData
import XCTest
@testable import marble

@MainActor
final class SprintVariantTests: MarbleTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = PersistenceController.makeContainer(useInMemory: true)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Target math

    func testTargetTenthsModeAndOutcomes() {
        let exact = SprintTargetTenths(lowerTenths: 148, upperTenths: 148)
        XCTAssertEqual(exact.mode, .time)
        XCTAssertTrue(exact.isValid)
        XCTAssertEqual(exact.outcome(forTenths: 147), .metTime)
        XCTAssertEqual(exact.outcome(forTenths: 148), .metTime)
        XCTAssertEqual(exact.outcome(forTenths: 149), .missedTime)
        XCTAssertEqual(exact.targetText(), "14.8s or faster")

        let range = SprintTargetTenths(lowerTenths: 145, upperTenths: 160)
        XCTAssertEqual(range.mode, .range)
        XCTAssertEqual(range.outcome(forTenths: 144), .fasterThanRange)
        XCTAssertEqual(range.outcome(forTenths: 145), .inRange)
        XCTAssertEqual(range.outcome(forTenths: 160), .inRange)
        XCTAssertEqual(range.outcome(forTenths: 161), .slowerThanRange)
        XCTAssertEqual(range.targetText(), "14.5–16.0s")
    }

    func testLegacySecondsRounding() {
        let target = SprintTargetTenths(lowerTenths: 145, upperTenths: 163)
        // Rounded to nearest whole second for the mirror columns.
        XCTAssertEqual(target.legacyLowerSeconds, 15)
        XCTAssertEqual(target.legacyUpperSeconds, 16)
        // The upper bound can never round below the lower.
        let inverted = SprintTargetTenths(lowerTenths: 148, upperTenths: 151)
        XCTAssertEqual(inverted.legacyLowerSeconds, 15)
        XCTAssertEqual(inverted.legacyUpperSeconds, 15)
    }

    // MARK: - Tenths evaluation

    func testTenthsEvaluationJudgesExactTenths() {
        let evaluation = SprintGoalEvaluation.evaluate(
            target: SprintTargetTenths(lowerTenths: 150, upperTenths: 150),
            prescribedDistance: 100,
            prescribedDistanceUnit: .meters,
            actualDistance: 100,
            actualDistanceUnit: .meters,
            actualTenths: 148
        )
        XCTAssertEqual(evaluation.status, SprintGoalStatus.hit)
        XCTAssertEqual(evaluation.actualText, "14.8s")
        XCTAssertTrue(evaluation.reason.contains("0.2 seconds faster"), evaluation.reason)

        let miss = SprintGoalEvaluation.evaluate(
            target: SprintTargetTenths(lowerTenths: 150, upperTenths: 150),
            prescribedDistance: 100,
            prescribedDistanceUnit: .meters,
            actualDistance: 100,
            actualDistanceUnit: .meters,
            actualTenths: 151
        )
        XCTAssertEqual(miss.status, SprintGoalStatus.missed)
        XCTAssertTrue(miss.reason.contains("0.1 seconds slower"), miss.reason)
    }

    func testSnapshotEvaluationPrefersDetailAndFallsBackWithoutOne() throws {
        let exercise = Exercise(
            name: "Sprint",
            category: .run,
            metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required),
            defaultRestSeconds: 60
        )
        context.insert(exercise)
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 100,
            distanceUnit: .meters,
            durationSeconds: 15,
            restAfterSeconds: 60
        )
        context.insert(entry)
        let snapshot = SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 100,
            distanceUnit: .meters,
            repetitionNumber: 1,
            repetitionCount: 4,
            targetLowerSeconds: 15,
            targetUpperSeconds: 15
        )

        // Legacy path: 15 s vs "15 s or faster" is a hit.
        let legacy = SprintGoalEvaluation.evaluate(snapshot: snapshot, entry: entry, detail: nil)
        XCTAssertEqual(legacy.status, SprintGoalStatus.hit)

        // The detail knows the truth was 15.2 against a 14.9 target: a miss
        // the whole-second columns could never see.
        let detail = SprintRepDetail(
            setEntryID: entry.id,
            durationTenths: 152,
            targetLowerTenths: 149,
            targetUpperTenths: 149
        )
        let precise = SprintGoalEvaluation.evaluate(snapshot: snapshot, entry: entry, detail: detail)
        XCTAssertEqual(precise.status, SprintGoalStatus.missed)
        XCTAssertEqual(precise.actualText, "15.2s")
    }

    // MARK: - Primary selection

    func testPrimaryPrefersMostRecentlyUsedValidVariant() {
        let exerciseID = UUID()
        let stale = SprintVariant(
            exerciseID: exerciseID,
            title: "Old",
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 90,
            targetUpperTenths: 90,
            lastUsedAt: now.addingTimeInterval(-3_600)
        )
        let fresh = SprintVariant(
            exerciseID: exerciseID,
            title: "New",
            distance: 150,
            distanceUnit: .meters,
            repetitionCount: 6,
            targetLowerTenths: 200,
            targetUpperTenths: 220,
            lastUsedAt: now
        )
        let invalid = SprintVariant(
            exerciseID: exerciseID,
            title: "Broken",
            distance: 0,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 90,
            targetUpperTenths: 90,
            lastUsedAt: now.addingTimeInterval(3_600)
        )
        let other = SprintVariant(
            exerciseID: UUID(),
            title: "Other exercise",
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 90,
            targetUpperTenths: 90,
            lastUsedAt: now.addingTimeInterval(7_200)
        )

        let primary = SprintVariant.primary(for: exerciseID, in: [stale, fresh, invalid, other])
        XCTAssertEqual(primary?.title, "New")
    }

    // MARK: - Adoption sweep

    func testAdoptionCreatesVariantFromValidPrescriptionOnce() throws {
        let exercise = Exercise(
            name: "Sprint",
            category: .run,
            preferredDistanceUnit: .yards,
            metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required),
            defaultRestSeconds: 60
        )
        context.insert(exercise)
        context.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 100,
            repetitionCount: 5,
            targetLowerSeconds: 13,
            targetUpperSeconds: 14
        ))
        try context.save()

        XCTAssertEqual(SprintVariant.adoptLegacyPrescriptions(in: context), 1)
        let variant = try XCTUnwrap(try context.fetch(FetchDescriptor<SprintVariant>()).first)
        XCTAssertEqual(variant.exerciseID, exercise.id)
        XCTAssertEqual(variant.targetLowerTenths, 130)
        XCTAssertEqual(variant.targetUpperTenths, 140)
        XCTAssertEqual(variant.distanceUnit, .yards, "Adoption honors the exercise's preferred unit")

        XCTAssertEqual(SprintVariant.adoptLegacyPrescriptions(in: context), 0, "Sweep must be idempotent")
    }

    // MARK: - Legacy mirror

    func testSyncLegacyPrescriptionMirrorsPrimaryVariantRounded() throws {
        let exerciseID = UUID()
        context.insert(SprintVariant(
            exerciseID: exerciseID,
            title: "Speed",
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 85,
            targetUpperTenths: 85,
            lastUsedAt: now
        ))
        context.insert(SprintVariant(
            exerciseID: exerciseID,
            title: "Tempo",
            distance: 150,
            distanceUnit: .meters,
            repetitionCount: 6,
            targetLowerTenths: 204,
            targetUpperTenths: 226,
            lastUsedAt: now.addingTimeInterval(-3_600)
        ))
        try context.save()

        SprintVariant.syncLegacyPrescription(for: exerciseID, in: context)
        let mirror = try XCTUnwrap(try context.fetch(FetchDescriptor<SprintPrescription>()).first)
        XCTAssertEqual(mirror.exerciseID, exerciseID)
        XCTAssertEqual(mirror.distance, 60)
        XCTAssertEqual(mirror.repetitionCount, 4)
        XCTAssertEqual(mirror.targetLowerSeconds, 9, "8.5 s rounds to 9 in the whole-second mirror")
        XCTAssertEqual(mirror.targetUpperSeconds, 9)

        // Deleting every variant removes the mirror too.
        for variant in try context.fetch(FetchDescriptor<SprintVariant>()) {
            context.delete(variant)
        }
        try context.save()
        SprintVariant.syncLegacyPrescription(for: exerciseID, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SprintPrescription>()).isEmpty)
    }

    // MARK: - Orphan sweeps

    func testRemoveOrphansDropsVariantsAndDetailsWithoutOwners() throws {
        let exercise = Exercise(
            name: "Sprint",
            category: .run,
            metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required),
            defaultRestSeconds: 60
        )
        context.insert(exercise)
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 60,
            distanceUnit: .meters,
            durationSeconds: 9,
            restAfterSeconds: 60
        )
        context.insert(entry)
        context.insert(SprintVariant(
            exerciseID: exercise.id,
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 90,
            targetUpperTenths: 90
        ))
        context.insert(SprintVariant(
            exerciseID: UUID(),
            distance: 60,
            distanceUnit: .meters,
            repetitionCount: 4,
            targetLowerTenths: 90,
            targetUpperTenths: 90
        ))
        context.insert(SprintRepDetail(
            setEntryID: entry.id,
            durationTenths: 88,
            targetLowerTenths: 90,
            targetUpperTenths: 90
        ))
        context.insert(SprintRepDetail(
            setEntryID: UUID(),
            durationTenths: 88,
            targetLowerTenths: 90,
            targetUpperTenths: 90
        ))
        try context.save()

        SprintVariant.removeOrphans(in: context)
        SprintRepDetail.removeOrphans(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintVariant>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintRepDetail>()), 1)
    }
}
