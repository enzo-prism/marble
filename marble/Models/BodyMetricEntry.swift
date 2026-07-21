import Foundation
import SwiftData

/// Where one body measurement came from. `String`-backed so the persisted value
/// is stable and human-readable, `nonisolated` because the target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin this Codable
/// value type to the main actor (see AGENTS.md) — HealthKit's completion
/// handlers construct these off it.
nonisolated enum BodyMetricSource: String, Codable, CaseIterable, Identifiable {
    /// The lifter typed it in.
    case manual
    /// Imported from an Apple Health `bodyMass` sample.
    case healthKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .healthKit:
            return "Apple Health"
        }
    }
}

/// One bodyweight (and optionally body-fat) measurement.
///
/// **Kilograms are canonical, always.** This model never stores mixed units —
/// that is the whole point of it existing rather than reusing `SetEntry`'s
/// weight/weightUnit pair. Marble has shipped four separate lb-vs-kg comparison
/// bugs, every one of them caused by summing or comparing raw values whose unit
/// lived in a sibling column. Entry converts to kg on save; display converts
/// back out via `LifterAnalytics.displayWeight(fromKilograms:in:)`.
///
/// Deliberately standalone: no `@Relationship` to `Exercise`, `SetEntry`, or
/// `WorkoutSession`. Bodyweight is a property of the lifter on a date, not of
/// any single set, and relationship churn in this schema is exactly what
/// resurrected the build-35 duplicate-checksum crash. Correlation with training
/// data is done by date in pure code (see `LifterAnalytics.nearestBodyweight`).
@Model
final class BodyMetricEntry {
    // Every read path here is "measurements in a date range, newest first" —
    // the Trends chart, the nearest-in-time DOTS lookup, and the HealthKit
    // dedup window. Index it like `SupplementEntry.takenAt` and
    // `SetEntry.performedAt` so those stay fast as history grows.
    #Index<BodyMetricEntry>([\.measuredAt])

    @Attribute(.unique) var id: UUID

    /// When the measurement was taken (not when it was logged).
    var measuredAt: Date

    /// Canonical kilograms. Never pounds. See the type doc above.
    var weightKilograms: Double

    /// Body fat as a percentage (0…100), when known.
    var bodyFatPercent: Double?

    var source: BodyMetricSource

    /// The originating HealthKit sample's `UUID`, for import dedup. Nil for
    /// manual entries. Not `@Attribute(.unique)` on purpose: a unique
    /// constraint on an optional would collide across every manual row's nil
    /// and force an upsert we don't want. The provider dedups by querying this
    /// column instead.
    var healthKitUUID: UUID?

    var notes: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        measuredAt: Date,
        weightKilograms: Double,
        bodyFatPercent: Double? = nil,
        source: BodyMetricSource = .manual,
        healthKitUUID: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.weightKilograms = weightKilograms
        self.bodyFatPercent = bodyFatPercent
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension BodyMetricEntry {
    /// The stored kilograms rendered in `unit`. The single conversion seam out
    /// of the canonical store — call this, never divide inline.
    func displayWeight(in unit: WeightUnit) -> Double {
        LifterAnalytics.displayWeight(fromKilograms: weightKilograms, in: unit)
    }

    /// Converts a user-entered value in `unit` into the canonical kilograms
    /// this model stores. The single conversion seam *into* the store.
    static func canonicalKilograms(from value: Double, unit: WeightUnit) -> Double {
        PersonalRecords.kilograms(value, unit: unit)
    }

    /// Bodyweight entries a plausible human could have logged. Guards the
    /// entry sheet and the HealthKit import against zero/garbage samples that
    /// would wreck the chart's Y domain and the DOTS denominator.
    static let plausibleKilograms: ClosedRange<Double> = 20...500

    static func isPlausible(kilograms: Double) -> Bool {
        plausibleKilograms.contains(kilograms)
    }
}
