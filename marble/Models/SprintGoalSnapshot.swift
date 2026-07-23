import Foundation
import SwiftData

/// The goal that was attached to one sprint rep when it was logged.
///
/// This is deliberately separate from `SprintPrescription`: exercise prescriptions
/// can be edited, while a historical result must always be judged against the goal
/// the athlete actually attempted that day.
@Model
final class SprintGoalSnapshot {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var setEntryID: UUID
    var exerciseID: UUID
    var distance: Double
    var distanceUnitRaw: String
    var repetitionNumber: Int?
    var repetitionCount: Int
    var targetLowerSeconds: Int
    var targetUpperSeconds: Int
    var isInferred: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        setEntryID: UUID,
        exerciseID: UUID,
        distance: Double,
        distanceUnit: DistanceUnit,
        repetitionNumber: Int?,
        repetitionCount: Int,
        targetLowerSeconds: Int,
        targetUpperSeconds: Int,
        isInferred: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.setEntryID = setEntryID
        self.exerciseID = exerciseID
        self.distance = distance
        self.distanceUnitRaw = distanceUnit.rawValue
        self.repetitionNumber = repetitionNumber
        self.repetitionCount = repetitionCount
        self.targetLowerSeconds = targetLowerSeconds
        self.targetUpperSeconds = targetUpperSeconds
        self.isInferred = isInferred
        self.createdAt = createdAt
    }
}

extension SprintGoalSnapshot {
    var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .meters
    }

    var plan: SprintPrescriptionPlan {
        SprintPrescriptionPlan(
            distance: distance,
            repetitionCount: repetitionCount,
            targetLowerSeconds: targetLowerSeconds,
            targetUpperSeconds: targetUpperSeconds
        )
    }

    var isValid: Bool {
        plan.isValid && repetitionNumber.map {
            (1...repetitionCount).contains($0)
        } != false
    }

    /// Referential-integrity sweep run from `SeedData` maintenance. `SetEntry`
    /// is the app's largest table and this used to load every one of its rows
    /// in full just to read `id`; both sides now project only the key column
    /// (`propertiesToFetch` — WWDC25 session 291), so the sweep touches two
    /// narrow indexed columns and, with zero orphans (the normal case since
    /// delete paths clean up as they go), never loads a complete model. The
    /// per-model `context.delete` is kept so the caller's save-or-rollback
    /// semantics stay exactly as before.
    static func removeOrphans(in context: ModelContext) {
        var entryIDsDescriptor = FetchDescriptor<SetEntry>()
        entryIDsDescriptor.propertiesToFetch = [\SetEntry.id]
        var snapshotKeysDescriptor = FetchDescriptor<SprintGoalSnapshot>()
        snapshotKeysDescriptor.propertiesToFetch = [\SprintGoalSnapshot.setEntryID]
        guard let setEntryIDs = try? Set(context.fetch(entryIDsDescriptor).map(\.id)),
              let snapshots = try? context.fetch(snapshotKeysDescriptor) else { return }
        snapshots
            .filter { !setEntryIDs.contains($0.setEntryID) }
            .forEach(context.delete)
    }

    /// Freezes the current sprint setup onto reps logged by builds that predate
    /// per-rep snapshots. The recovered provenance remains explicit in the UI.
    ///
    /// Perf shape: this used to load *four whole tables* — including every
    /// `SetEntry` ever logged — into arrays just to skip most rows in a loop.
    /// The loop's own eligibility guards are now pushed into the store (WWDC25
    /// session 291): only entries with both a distance and a duration whose
    /// exercise actually has a prescription are candidates, existing-snapshot
    /// keys are projected via `propertiesToFetch`, and the candidate traversal
    /// is a batched `context.enumerate` (WWDC23 session 10196) so a legacy
    /// multi-year log never materializes as one resident array. The `Exercise`
    /// table fetch is gone entirely — `entry.exercise` is the same row the
    /// dictionary lookup used to rediscover by ID.
    @discardableResult
    static func backfillLegacyEntries(in context: ModelContext) -> Int {
        guard let prescriptions = try? context.fetch(FetchDescriptor<SprintPrescription>()) else { return 0 }
        let prescriptionByExerciseID = Dictionary(
            prescriptions.map { ($0.exerciseID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // No prescriptions means no entry can qualify; skip the big table.
        guard !prescriptionByExerciseID.isEmpty else { return 0 }
        let prescribedExerciseIDs = Array(prescriptionByExerciseID.keys)

        var snapshotKeysDescriptor = FetchDescriptor<SprintGoalSnapshot>()
        snapshotKeysDescriptor.propertiesToFetch = [\SprintGoalSnapshot.setEntryID]
        guard let snapshots = try? context.fetch(snapshotKeysDescriptor) else { return 0 }
        let existingSetIDs = Set(snapshots.map(\.setEntryID))

        let candidatesDescriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate {
                $0.distance != nil
                    && $0.durationSeconds != nil
                    && prescribedExerciseIDs.contains($0.exercise.id)
            }
        )
        var inserted = 0
        // `allowEscapingMutations` because the block inserts snapshots into
        // the same context mid-traversal; inserting a *different* model type
        // does not invalidate the SetEntry batch being enumerated.
        try? context.enumerate(candidatesDescriptor, allowEscapingMutations: true) { entry in
            guard !existingSetIDs.contains(entry.id),
                  let prescription = prescriptionByExerciseID[entry.exercise.id],
                  prescription.isValid else { return }

            context.insert(SprintGoalSnapshot(
                setEntryID: entry.id,
                exerciseID: entry.exercise.id,
                distance: prescription.distance,
                distanceUnit: entry.exercise.preferredDistanceUnit,
                repetitionNumber: nil,
                repetitionCount: prescription.repetitionCount,
                targetLowerSeconds: prescription.targetLowerSeconds,
                targetUpperSeconds: prescription.targetUpperSeconds,
                isInferred: true,
                createdAt: entry.createdAt
            ))
            inserted += 1
        }
        return inserted
    }
}

enum SprintGoalStatus: Equatable {
    case hit
    case missed
    case notScored

    var title: String {
        switch self {
        case .hit: "Goal hit"
        case .missed: "Goal missed"
        case .notScored: "Not scored"
        }
    }
}

/// A display-ready, pure evaluation of one sprint rep against its frozen goal.
struct SprintGoalEvaluation: Equatable {
    let status: SprintGoalStatus
    let outcome: SprintTargetOutcome?
    let actualText: String?
    let targetText: String
    let reason: String

    var didHit: Bool { status == .hit }

    static func evaluate(
        plan: SprintPrescriptionPlan,
        prescribedDistanceUnit: DistanceUnit,
        actualDistance: Double?,
        actualDistanceUnit: DistanceUnit,
        actualSeconds: Int?
    ) -> SprintGoalEvaluation {
        let targetText = plan.targetText()
        guard plan.isValid else {
            return SprintGoalEvaluation(
                status: .notScored,
                outcome: nil,
                actualText: actualSeconds.flatMap { $0 > 0 ? timeText($0) : nil },
                targetText: targetText,
                reason: "This rep's saved sprint goal is invalid."
            )
        }

        guard let actualDistance, actualDistance > 0 else {
            return SprintGoalEvaluation(
                status: .notScored,
                outcome: nil,
                actualText: actualSeconds.flatMap { $0 > 0 ? timeText($0) : nil },
                targetText: targetText,
                reason: "Add the sprint distance to score this rep."
            )
        }

        let prescribedMeters = prescribedDistanceUnit.meters(from: plan.distance)
        let actualMeters = actualDistanceUnit.meters(from: actualDistance)
        let distanceToleranceMeters = max(0.01, prescribedMeters * 0.000_001)
        guard abs(prescribedMeters - actualMeters) <= distanceToleranceMeters else {
            return SprintGoalEvaluation(
                status: .notScored,
                outcome: nil,
                actualText: actualSeconds.flatMap { $0 > 0 ? timeText($0) : nil },
                targetText: targetText,
                reason: "This rep was \(distanceText(actualDistance, unit: actualDistanceUnit)), not the prescribed \(distanceText(plan.distance, unit: prescribedDistanceUnit))."
            )
        }

        guard let actualSeconds, actualSeconds > 0 else {
            return SprintGoalEvaluation(
                status: .notScored,
                outcome: nil,
                actualText: nil,
                targetText: targetText,
                reason: "Add a sprint time to see whether this rep hit the goal."
            )
        }

        let outcome = plan.outcome(for: actualSeconds)
        let status: SprintGoalStatus = switch outcome {
        case .metTime, .inRange: .hit
        case .missedTime, .fasterThanRange, .slowerThanRange: .missed
        case nil: .notScored
        }

        return SprintGoalEvaluation(
            status: status,
            outcome: outcome,
            actualText: timeText(actualSeconds),
            targetText: targetText,
            reason: reason(for: outcome, actualSeconds: actualSeconds, plan: plan)
        )
    }

    @MainActor
    static func evaluate(snapshot: SprintGoalSnapshot, entry: SetEntry) -> SprintGoalEvaluation {
        evaluate(
            plan: snapshot.plan,
            prescribedDistanceUnit: snapshot.distanceUnit,
            actualDistance: entry.distance,
            actualDistanceUnit: entry.distanceUnit,
            actualSeconds: entry.durationSeconds
        )
    }

    private static func reason(
        for outcome: SprintTargetOutcome?,
        actualSeconds: Int,
        plan: SprintPrescriptionPlan
    ) -> String {
        let actual = timeText(actualSeconds)
        switch outcome {
        case .metTime:
            let difference = plan.targetLowerSeconds - actualSeconds
            if difference == 0 {
                return "\(actual) matched your \(timeText(plan.targetLowerSeconds))-or-faster goal."
            }
            return "\(actual) was \(deltaText(difference)) faster than your \(timeText(plan.targetLowerSeconds))-or-faster goal."
        case .missedTime:
            let difference = actualSeconds - plan.targetLowerSeconds
            return "\(actual) was \(deltaText(difference)) slower than your \(timeText(plan.targetLowerSeconds))-or-faster goal."
        case .fasterThanRange:
            let difference = plan.targetLowerSeconds - actualSeconds
            return "\(actual) was \(deltaText(difference)) faster than the \(timeText(plan.targetLowerSeconds)) lower limit."
        case .inRange:
            return "\(actual) was inside your target range of \(plan.targetText())."
        case .slowerThanRange:
            let difference = actualSeconds - plan.targetUpperSeconds
            return "\(actual) was \(deltaText(difference)) slower than the \(timeText(plan.targetUpperSeconds)) upper limit."
        case nil:
            return "This rep could not be scored."
        }
    }

    private static func timeText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : DateHelper.formattedClockDuration(seconds: seconds)
    }

    private static func deltaText(_ seconds: Int) -> String {
        seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private static func distanceText(_ distance: Double, unit: DistanceUnit) -> String {
        let formatted = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        return "\(formatted) \(unit.symbol)"
    }
}
