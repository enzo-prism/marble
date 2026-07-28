import Foundation
import SwiftData

/// The tenths-precision target attached to one sprint variant or frozen onto
/// one rep. Lower == upper means "this time or faster"; lower < upper is an
/// inclusive range — the same two modes as `SprintPrescriptionPlan`, carried
/// in canonical tenths (see `SprintTiming`).
nonisolated struct SprintTargetTenths: Equatable {
    var lowerTenths: Int
    var upperTenths: Int

    var mode: SprintTargetMode {
        lowerTenths == upperTenths ? .time : .range
    }

    var isValid: Bool {
        lowerTenths > 0 && upperTenths >= lowerTenths &&
        SprintTiming.isPlausible(tenths: lowerTenths) &&
        SprintTiming.isPlausible(tenths: upperTenths)
    }

    /// The whole-second bounds mirrored into the legacy `SprintPrescription` /
    /// `SprintGoalSnapshot` columns for surfaces (and old backups) that predate
    /// tenths. Rounded to nearest, never re-read as the source of truth by any
    /// tenths-aware path.
    var legacyLowerSeconds: Int { max(1, SprintTiming.wholeSeconds(fromTenths: lowerTenths)) }
    var legacyUpperSeconds: Int { max(legacyLowerSeconds, SprintTiming.wholeSeconds(fromTenths: upperTenths)) }

    func outcome(forTenths actualTenths: Int) -> SprintTargetOutcome? {
        guard actualTenths > 0 else { return nil }
        switch mode {
        case .time:
            return actualTenths <= lowerTenths ? .metTime : .missedTime
        case .range:
            if actualTenths < lowerTenths { return .fasterThanRange }
            if actualTenths > upperTenths { return .slowerThanRange }
            return .inRange
        }
    }

    func targetText() -> String {
        switch mode {
        case .time:
            return "\(SprintTiming.text(tenths: lowerTenths)) or faster"
        case .range:
            let lower = SprintTiming.text(tenths: lowerTenths)
            let upper = SprintTiming.text(tenths: upperTenths)
            // Drop the duplicated unit on the fast end for sub-minute ranges,
            // matching the legacy "19–21s" shape: "14.5–16.0s".
            if lowerTenths < 600, upperTenths < 600 {
                return "\(String(lower.dropLast()))–\(upper)"
            }
            return "\(lower)–\(upper)"
        }
    }
}

/// Value snapshot of one sprint variant for view state (`AddSetView` snapshots
/// exercises the same way — the sheet must keep working if the backing row is
/// edited or deleted mid-flow).
nonisolated struct SprintVariantValue: Equatable, Identifiable {
    /// Nil when synthesized from a legacy `SprintPrescription` that has no
    /// variant row yet (fixture stores, mid-adoption edge). A nil id logs the
    /// rep without touching `lastUsedAt` or writing a `variantID`.
    let id: UUID?
    let title: String
    let distance: Double
    let distanceUnit: DistanceUnit
    let repetitionCount: Int
    let target: SprintTargetTenths

    init(_ variant: SprintVariant) {
        id = variant.id
        title = variant.title
        distance = variant.distance
        distanceUnit = variant.distanceUnit
        repetitionCount = variant.repetitionCount
        target = variant.target
    }

    init(legacyPlan plan: SprintPrescriptionPlan, distanceUnit: DistanceUnit) {
        id = nil
        title = ""
        distance = plan.distance
        self.distanceUnit = distanceUnit
        repetitionCount = plan.repetitionCount
        target = SprintTargetTenths(
            lowerTenths: SprintTiming.tenths(fromWholeSeconds: plan.targetLowerSeconds),
            upperTenths: SprintTiming.tenths(fromWholeSeconds: plan.targetUpperSeconds)
        )
    }

    /// "Speed" when titled, otherwise "4 × 60 m" — the menu label.
    var displayName: String {
        if !title.isEmpty { return title }
        let formatted = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        return "\(repetitionCount) × \(formatted) \(distanceUnit.symbol)"
    }

    func formattedDistance() -> String {
        let formatted = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        return "\(formatted) \(distanceUnit.symbol)"
    }

    /// The card's one-line plan summary, same shape as
    /// `SprintPrescriptionPlan.summary(distanceUnit:restSeconds:)`.
    func summary(restSeconds: Int) -> String {
        "\(repetitionCount) × \(formattedDistance()) · target \(target.targetText()) · \(DateHelper.formattedDuration(seconds: restSeconds)) rest"
    }

    /// The rounded whole-second bounds for the legacy `SprintGoalSnapshot`
    /// every rep still writes.
    var legacyPlan: SprintPrescriptionPlan {
        SprintPrescriptionPlan(
            distance: distance,
            repetitionCount: repetitionCount,
            targetLowerSeconds: target.legacyLowerSeconds,
            targetUpperSeconds: target.legacyUpperSeconds
        )
    }
}

/// One reusable sprint plan for an exercise — "60 m speed", "150 m tempo".
///
/// This is the multi-prescription successor to `SprintPrescription`, which is
/// hard-limited to one plan per exercise by its unique `exerciseID` column.
/// That constraint cannot be lifted in place (modifying a shipped entity is
/// the checksum trap documented in `MarbleSchema`), so variants are a new
/// additive V6 model and the old prescription lives on as a **mirror of the
/// primary (most recently used) variant**, kept in sync by
/// `syncLegacyPrescription(for:in:)` so every legacy surface and pre-V6 backup
/// stays truthful.
///
/// References the exercise by raw UUID, never `@Relationship` — the
/// load-bearing style called out in the V5 schema comment.
@Model
final class SprintVariant {
    @Attribute(.unique) var id: UUID
    /// Deliberately NOT unique — multiple variants per exercise is the point.
    var exerciseID: UUID
    /// Optional athlete-facing name ("Speed", "Tempo"). Empty falls back to
    /// the distance summary in every display path.
    var title: String
    var distance: Double
    var distanceUnitRaw: String
    var repetitionCount: Int
    /// Canonical tenths (see `SprintTiming`). 145 == 14.5 s.
    var targetLowerTenths: Int
    var targetUpperTenths: Int
    /// Drives which variant a fresh logging session preselects and which one
    /// the legacy mirror reflects: most recent wins.
    var lastUsedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        title: String = "",
        distance: Double,
        distanceUnit: DistanceUnit,
        repetitionCount: Int,
        targetLowerTenths: Int,
        targetUpperTenths: Int,
        lastUsedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.title = title
        self.distance = distance
        self.distanceUnitRaw = distanceUnit.rawValue
        self.repetitionCount = repetitionCount
        self.targetLowerTenths = targetLowerTenths
        self.targetUpperTenths = targetUpperTenths
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SprintVariant {
    var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .meters
    }

    var target: SprintTargetTenths {
        SprintTargetTenths(lowerTenths: targetLowerTenths, upperTenths: targetUpperTenths)
    }

    var isValid: Bool {
        distance > 0 && (1...50).contains(repetitionCount) && target.isValid
    }

    /// The whole-second plan mirrored into legacy surfaces.
    var legacyPlan: SprintPrescriptionPlan {
        SprintPrescriptionPlan(
            distance: distance,
            repetitionCount: repetitionCount,
            targetLowerSeconds: target.legacyLowerSeconds,
            targetUpperSeconds: target.legacyUpperSeconds
        )
    }

    /// "Speed · 4 × 60 m · target 8.5s or faster" (title omitted when empty).
    func summary() -> String {
        let formattedDistance = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        let core = "\(repetitionCount) × \(formattedDistance) \(distanceUnit.symbol) · target \(target.targetText())"
        return title.isEmpty ? core : "\(title) · \(core)"
    }

    /// The variant a fresh logging session for `exerciseID` should preselect.
    static func primary(for exerciseID: UUID, in variants: [SprintVariant]) -> SprintVariant? {
        variants
            .filter { $0.exerciseID == exerciseID && $0.isValid }
            .max { lhs, rhs in
                if lhs.lastUsedAt == rhs.lastUsedAt { return lhs.createdAt < rhs.createdAt }
                return lhs.lastUsedAt < rhs.lastUsedAt
            }
    }

    /// Idempotent adoption sweep: every valid legacy `SprintPrescription`
    /// whose exercise has no variant yet gets one, tenths = seconds × 10.
    ///
    /// Runs on every launch (both tables are small and key-projected) rather
    /// than behind a one-time flag, because legacy prescriptions can reappear
    /// at any time — restoring a pre-V6 backup recreates them — and each one
    /// must become loggable as a variant without waiting for a reinstall.
    @discardableResult
    static func adoptLegacyPrescriptions(in context: ModelContext) -> Int {
        guard let prescriptions = try? context.fetch(FetchDescriptor<SprintPrescription>()),
              !prescriptions.isEmpty else { return 0 }
        var variantExerciseDescriptor = FetchDescriptor<SprintVariant>()
        variantExerciseDescriptor.propertiesToFetch = [\SprintVariant.exerciseID]
        guard let existing = try? context.fetch(variantExerciseDescriptor) else { return 0 }
        let coveredExerciseIDs = Set(existing.map(\.exerciseID))

        var adopted = 0
        for prescription in prescriptions where prescription.isValid && !coveredExerciseIDs.contains(prescription.exerciseID) {
            // The adopting exercise's preferred unit is not fetched here; the
            // prescription never stored one (its editor always paired it with
            // the exercise row), so meters — the editor's only preset unit —
            // is the correct default and the variant editor can fix outliers.
            let exercise = try? context.fetch(FetchDescriptor<Exercise>(
                predicate: exercisePredicate(for: prescription.exerciseID)
            )).first
            context.insert(SprintVariant(
                exerciseID: prescription.exerciseID,
                distance: prescription.distance,
                distanceUnit: exercise?.preferredDistanceUnit ?? .meters,
                repetitionCount: prescription.repetitionCount,
                targetLowerTenths: SprintTiming.tenths(fromWholeSeconds: prescription.targetLowerSeconds),
                targetUpperTenths: SprintTiming.tenths(fromWholeSeconds: prescription.targetUpperSeconds),
                lastUsedAt: prescription.updatedAt,
                createdAt: prescription.createdAt,
                updatedAt: prescription.updatedAt
            ))
            adopted += 1
        }
        return adopted
    }

    private static func exercisePredicate(for exerciseID: UUID) -> Predicate<Exercise> {
        #Predicate { $0.id == exerciseID }
    }

    /// Re-mirrors the exercise's legacy `SprintPrescription` from its primary
    /// variant (rounded to whole seconds), or deletes the mirror when no valid
    /// variant remains. Call after any variant create/edit/delete/selection.
    static func syncLegacyPrescription(for exerciseID: UUID, in context: ModelContext) {
        let variants = (try? context.fetch(FetchDescriptor<SprintVariant>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        ))) ?? []
        let existing = (try? context.fetch(FetchDescriptor<SprintPrescription>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        )))?.first

        guard let primary = primary(for: exerciseID, in: variants) else {
            if let existing { context.delete(existing) }
            return
        }
        let plan = primary.legacyPlan
        if let existing {
            if existing.distance != plan.distance
                || existing.repetitionCount != plan.repetitionCount
                || existing.targetLowerSeconds != plan.targetLowerSeconds
                || existing.targetUpperSeconds != plan.targetUpperSeconds {
                existing.distance = plan.distance
                existing.repetitionCount = plan.repetitionCount
                existing.targetLowerSeconds = plan.targetLowerSeconds
                existing.targetUpperSeconds = plan.targetUpperSeconds
                existing.updatedAt = primary.updatedAt
            }
        } else {
            context.insert(SprintPrescription(
                exerciseID: exerciseID,
                distance: plan.distance,
                repetitionCount: plan.repetitionCount,
                targetLowerSeconds: plan.targetLowerSeconds,
                targetUpperSeconds: plan.targetUpperSeconds,
                createdAt: primary.createdAt,
                updatedAt: primary.updatedAt
            ))
        }
    }

    /// Referential-integrity sweep, same key-projected shape as
    /// `SprintPrescription.removeOrphans`.
    static func removeOrphans(in context: ModelContext) {
        var exerciseIDsDescriptor = FetchDescriptor<Exercise>()
        exerciseIDsDescriptor.propertiesToFetch = [\Exercise.id]
        var variantKeysDescriptor = FetchDescriptor<SprintVariant>()
        variantKeysDescriptor.propertiesToFetch = [\SprintVariant.exerciseID]
        guard let exerciseIDs = try? Set(context.fetch(exerciseIDsDescriptor).map(\.id)),
              let variants = try? context.fetch(variantKeysDescriptor) else { return }
        variants
            .filter { !exerciseIDs.contains($0.exerciseID) }
            .forEach(context.delete)
    }
}
