import Foundation
import SwiftData

enum SprintTargetMode: String, CaseIterable, Identifiable {
    case time
    case range

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Time"
        case .range: return "Range"
        }
    }
}

enum SprintTargetOutcome: Equatable {
    case metTime
    case missedTime
    case fasterThanRange
    case inRange
    case slowerThanRange

    var title: String {
        switch self {
        case .metTime: return "Goal met"
        case .missedTime: return "Slower than goal"
        case .fasterThanRange: return "Faster than target range"
        case .inRange: return "In target range"
        case .slowerThanRange: return "Slower than target range"
        }
    }
}

struct SprintPrescriptionPlan: Equatable {
    var distance: Double
    var repetitionCount: Int
    var targetLowerSeconds: Int
    var targetUpperSeconds: Int

    var targetMode: SprintTargetMode {
        targetLowerSeconds == targetUpperSeconds ? .time : .range
    }

    var isValid: Bool {
        distance > 0 &&
        (1...50).contains(repetitionCount) &&
        targetLowerSeconds > 0 &&
        targetUpperSeconds >= targetLowerSeconds
    }

    func targetText() -> String {
        switch targetMode {
        case .time:
            return "\(Self.timeText(targetLowerSeconds)) or faster"
        case .range:
            if targetLowerSeconds < 60, targetUpperSeconds < 60 {
                return "\(targetLowerSeconds)–\(targetUpperSeconds)s"
            }
            return "\(Self.timeText(targetLowerSeconds))–\(Self.timeText(targetUpperSeconds))"
        }
    }

    func summary(distanceUnit: DistanceUnit, restSeconds: Int) -> String {
        let formattedDistance = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        return "\(repetitionCount) × \(formattedDistance) \(distanceUnit.symbol) · target \(targetText()) · \(DateHelper.formattedDuration(seconds: restSeconds)) rest"
    }

    func outcome(for actualSeconds: Int) -> SprintTargetOutcome? {
        guard actualSeconds > 0 else { return nil }
        switch targetMode {
        case .time:
            return actualSeconds <= targetLowerSeconds ? .metTime : .missedTime
        case .range:
            if actualSeconds < targetLowerSeconds { return .fasterThanRange }
            if actualSeconds > targetUpperSeconds { return .slowerThanRange }
            return .inRange
        }
    }

    private static func timeText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : DateHelper.formattedClockDuration(seconds: seconds)
    }
}

/// A reusable sprint prescription attached to an exercise by UUID. Keeping this as
/// its own additive model preserves the shipped Exercise and SetEntry checksums.
@Model
final class SprintPrescription {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var exerciseID: UUID
    var distance: Double
    var repetitionCount: Int
    var targetLowerSeconds: Int
    var targetUpperSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        distance: Double,
        repetitionCount: Int,
        targetLowerSeconds: Int,
        targetUpperSeconds: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.distance = distance
        self.repetitionCount = repetitionCount
        self.targetLowerSeconds = targetLowerSeconds
        self.targetUpperSeconds = targetUpperSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SprintPrescription {
    /// Referential-integrity sweep run from `SeedData` maintenance. This used
    /// to materialize every `Exercise` and every prescription in full just to
    /// compare two UUID columns; both fetches now project only the key column
    /// they need (`propertiesToFetch` — the WWDC25 session 291 guidance), so
    /// in the normal zero-orphan case no complete row is ever loaded. The
    /// per-model `context.delete` is kept (rather than a batch delete) so the
    /// caller's save-or-rollback semantics stay exactly as before.
    static func removeOrphans(in context: ModelContext) {
        var exerciseIDsDescriptor = FetchDescriptor<Exercise>()
        exerciseIDsDescriptor.propertiesToFetch = [\Exercise.id]
        var prescriptionKeysDescriptor = FetchDescriptor<SprintPrescription>()
        prescriptionKeysDescriptor.propertiesToFetch = [\SprintPrescription.exerciseID]
        guard let exerciseIDs = try? Set(context.fetch(exerciseIDsDescriptor).map(\.id)),
              let prescriptions = try? context.fetch(prescriptionKeysDescriptor) else { return }
        prescriptions
            .filter { !exerciseIDs.contains($0.exerciseID) }
            .forEach(context.delete)
    }

    var plan: SprintPrescriptionPlan {
        SprintPrescriptionPlan(
            distance: distance,
            repetitionCount: repetitionCount,
            targetLowerSeconds: targetLowerSeconds,
            targetUpperSeconds: targetUpperSeconds
        )
    }

    var targetMode: SprintTargetMode {
        plan.targetMode
    }

    var isValid: Bool {
        plan.isValid
    }

    func targetText() -> String {
        plan.targetText()
    }

    func summary(distanceUnit: DistanceUnit, restSeconds: Int) -> String {
        plan.summary(distanceUnit: distanceUnit, restSeconds: restSeconds)
    }

    func outcome(for actualSeconds: Int) -> SprintTargetOutcome? {
        plan.outcome(for: actualSeconds)
    }
}
