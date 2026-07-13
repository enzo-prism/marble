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

    static func removeOrphans(in context: ModelContext) {
        guard let setEntryIDs = try? Set(context.fetch(FetchDescriptor<SetEntry>()).map(\.id)),
              let snapshots = try? context.fetch(FetchDescriptor<SprintGoalSnapshot>()) else { return }
        snapshots
            .filter { !setEntryIDs.contains($0.setEntryID) }
            .forEach(context.delete)
    }

    /// Freezes the current sprint setup onto reps logged by builds that predate
    /// per-rep snapshots. The recovered provenance remains explicit in the UI.
    @discardableResult
    static func backfillLegacyEntries(in context: ModelContext) -> Int {
        guard let entries = try? context.fetch(FetchDescriptor<SetEntry>()),
              let exercises = try? context.fetch(FetchDescriptor<Exercise>()),
              let prescriptions = try? context.fetch(FetchDescriptor<SprintPrescription>()),
              let snapshots = try? context.fetch(FetchDescriptor<SprintGoalSnapshot>()) else { return 0 }

        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let prescriptionByExerciseID = Dictionary(
            prescriptions.map { ($0.exerciseID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingSetIDs = Set(snapshots.map(\.setEntryID))
        var inserted = 0

        for entry in entries where !existingSetIDs.contains(entry.id) {
            guard let exercise = exerciseByID[entry.exercise.id],
                  let prescription = prescriptionByExerciseID[exercise.id],
                  prescription.isValid,
                  entry.distance != nil,
                  entry.durationSeconds != nil else { continue }

            context.insert(SprintGoalSnapshot(
                setEntryID: entry.id,
                exerciseID: exercise.id,
                distance: prescription.distance,
                distanceUnit: exercise.preferredDistanceUnit,
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
