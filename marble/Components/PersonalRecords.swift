import Foundation

/// The strength personal records Marble celebrates.
///
/// Scope is deliberately weight & reps only — the two dimensions a lifter
/// is trying to push set over set. Cardio/timed bests live in Trends.
struct PersonalRecordBadge: OptionSet, Hashable {
    let rawValue: Int

    static let weight = PersonalRecordBadge(rawValue: 1 << 0)
    static let reps = PersonalRecordBadge(rawValue: 1 << 1)

    /// Short label for the celebratory pill in the journal. Collapses a
    /// weight+reps record to a single "PR" so the badge stays compact.
    var shortTitle: String {
        if contains(.weight) && contains(.reps) { return "PR" }
        if contains(.weight) { return "Weight PR" }
        if contains(.reps) { return "Reps PR" }
        return "PR"
    }

    /// Spoken description for VoiceOver.
    var accessibilityDescription: String {
        if contains(.weight) && contains(.reps) { return "Personal record: weight and reps" }
        if contains(.weight) { return "Personal record: weight" }
        if contains(.reps) { return "Personal record: reps" }
        return "Personal record"
    }
}

/// All-time personal bests plus the "usual" working ranges for one exercise.
/// Holds the actual `SetEntry` references so callers can format weight with the
/// exercise's own resistance-tracking style (e.g. dumbbell per-hand display).
struct ExercisePersonalRecords {
    let exerciseID: UUID
    /// Heaviest set ever (unit-normalized). Tie-break: more reps, then later date.
    let heaviestEntry: SetEntry?
    /// Most reps ever. Tie-break: heavier, then later date.
    let mostRepsEntry: SetEntry?
    /// Typical weight range over a recent window, expressed in display units
    /// (per-hand for dumbbell pairs) and in `usualWeightUnit`.
    let usualWeightRange: ClosedRange<Double>?
    let usualWeightUnit: WeightUnit?
    /// Typical rep range over a recent window.
    let usualRepsRange: ClosedRange<Int>?
    /// Total logged sets for this exercise (drives empty-state copy).
    let totalSets: Int

    var hasAnyBest: Bool { heaviestEntry != nil || mostRepsEntry != nil }

    static func empty(exerciseID: UUID) -> ExercisePersonalRecords {
        ExercisePersonalRecords(
            exerciseID: exerciseID,
            heaviestEntry: nil,
            mostRepsEntry: nil,
            usualWeightRange: nil,
            usualWeightUnit: nil,
            usualRepsRange: nil,
            totalSets: 0
        )
    }
}

/// Pure, unit-testable engine for personal-record detection.
enum PersonalRecords {
    /// Float tolerance so re-logging an identical weight isn't counted as a new record.
    static let weightEpsilon = 0.0001
    /// How many recent sets define the "usual" range.
    static let usualWindow = 10
    /// Pounds → kilograms (exact NIST factor) for unit-agnostic comparison.
    private static let poundsToKilograms = 0.45359237

    /// Normalizes a weight to kilograms so records compare correctly across lb/kg.
    static func kilograms(_ weight: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return weight
        case .lb: return weight * poundsToKilograms
        }
    }

    /// Walks every exercise's sets in chronological order and returns, for each
    /// record-setting set, which records it broke at the time it was logged.
    ///
    /// A set earns a badge when it strictly exceeds the running best (by weight
    /// or by reps) of all sets performed before it. The first set with a value
    /// establishes the baseline record and is badged too — so a lifter sees a
    /// trail of every personal best in their history, and the all-time best is
    /// always badged. Weight & reps only; only for exercises that use the metric.
    static func badges(for entries: [SetEntry]) -> [UUID: PersonalRecordBadge] {
        var result: [UUID: PersonalRecordBadge] = [:]
        let grouped = Dictionary(grouping: entries) { $0.exercise.id }

        for (_, group) in grouped {
            guard let sample = group.first else { continue }
            let usesWeight = sample.exercise.metrics.usesWeight
            let usesReps = sample.exercise.metrics.usesReps
            guard usesWeight || usesReps else { continue }

            let ordered = group.sorted(by: isChronologicallyBefore)
            var bestKilograms: Double?
            var bestReps: Int?

            for entry in ordered {
                var badge: PersonalRecordBadge = []

                if usesWeight, let weight = entry.weight, weight > 0 {
                    let kilos = kilograms(weight, unit: entry.weightUnit)
                    if let current = bestKilograms {
                        if kilos > current + weightEpsilon {
                            badge.insert(.weight)
                            bestKilograms = kilos
                        }
                    } else {
                        badge.insert(.weight)
                        bestKilograms = kilos
                    }
                }

                if usesReps, let reps = entry.reps, reps > 0 {
                    if let current = bestReps {
                        if reps > current {
                            badge.insert(.reps)
                            bestReps = reps
                        }
                    } else {
                        badge.insert(.reps)
                        bestReps = reps
                    }
                }

                if !badge.isEmpty {
                    result[entry.id] = badge
                }
            }
        }

        return result
    }

    /// All-time bests and usual ranges for a single exercise.
    static func records(for exercise: Exercise, entries allEntries: [SetEntry]) -> ExercisePersonalRecords {
        let entries = allEntries.filter { $0.exercise.id == exercise.id }
        guard !entries.isEmpty else { return .empty(exerciseID: exercise.id) }

        let usesWeight = exercise.metrics.usesWeight
        let usesReps = exercise.metrics.usesReps

        let heaviest = usesWeight ? entries
            .filter { ($0.weight ?? 0) > 0 }
            .max(by: heaviestIsLessThan) : nil

        let mostReps = usesReps ? entries
            .filter { ($0.reps ?? 0) > 0 }
            .max(by: mostRepsIsLessThan) : nil

        let recent = entries.sorted { $0.performedAt > $1.performedAt }.prefix(usualWindow)

        // Usual weight range, in the dominant recent unit and display values.
        var usualWeightRange: ClosedRange<Double>?
        var usualWeightUnit: WeightUnit?
        if usesWeight {
            let weighted = recent.filter { ($0.weight ?? 0) > 0 }
            if let unit = dominantWeightUnit(in: weighted) {
                let displayWeights = weighted
                    .filter { $0.weightUnit == unit }
                    .compactMap { exercise.displayedWeightInput(from: $0.weight) }
                if displayWeights.count >= 2, let lo = displayWeights.min(), let hi = displayWeights.max() {
                    usualWeightRange = lo...hi
                    usualWeightUnit = unit
                }
            }
        }

        // Usual rep range.
        var usualRepsRange: ClosedRange<Int>?
        if usesReps {
            let reps = recent.compactMap { $0.reps }.filter { $0 > 0 }
            if reps.count >= 2, let lo = reps.min(), let hi = reps.max() {
                usualRepsRange = lo...hi
            }
        }

        return ExercisePersonalRecords(
            exerciseID: exercise.id,
            heaviestEntry: heaviest,
            mostRepsEntry: mostReps,
            usualWeightRange: usualWeightRange,
            usualWeightUnit: usualWeightUnit,
            usualRepsRange: usualRepsRange,
            totalSets: entries.count
        )
    }

    /// Which records a candidate entry would beat versus the supplied bests.
    ///
    /// Powers the live "New PR!" indicator while logging. Unlike `badges(for:)`
    /// this only fires when there is an existing record to beat — the very first
    /// set isn't announced as a PR mid-entry (it's celebrated once saved).
    static func projectedBadge(
        storedWeight: Double?,
        weightUnit: WeightUnit,
        reps: Int?,
        beating records: ExercisePersonalRecords?,
        metrics: ExerciseMetricsProfile
    ) -> PersonalRecordBadge {
        var badge: PersonalRecordBadge = []

        if metrics.usesWeight,
           let candidate = storedWeight, candidate > 0,
           let best = records?.heaviestEntry, let bestWeight = best.weight {
            if kilograms(candidate, unit: weightUnit) > kilograms(bestWeight, unit: best.weightUnit) + weightEpsilon {
                badge.insert(.weight)
            }
        }

        if metrics.usesReps,
           let candidate = reps, candidate > 0,
           let bestReps = records?.mostRepsEntry?.reps {
            if candidate > bestReps {
                badge.insert(.reps)
            }
        }

        return badge
    }

    // MARK: - PR proximity

    /// A record close enough to reach today, framed as opportunity BEFORE the
    /// attempt ("a rep-PR is in reach") — goal-gradient research says effort
    /// rises near a target, but only when it reads as controllable, never as
    /// a missed target afterwards.
    enum ProximityCue: Equatable {
        case weight(deltaText: String)
        case reps(delta: Int)

        var message: String {
            switch self {
            case .weight(let deltaText):
                return "You're \(deltaText) from a weight PR — in reach today."
            case .reps(let delta):
                return delta == 1
                    ? "1 rep past your usual top is a rep PR — in reach today."
                    : "\(delta) reps past your usual top is a rep PR — in reach today."
            }
        }
    }

    /// Weight records within this fraction of the usual working top count
    /// as "in reach"; anything further is a program goal, not a today goal.
    static let proximityWeightFraction = 0.05
    /// Rep records at most this many reps past the usual top count as in reach.
    static let proximityRepWindow = 2

    static func proximityCue(for records: ExercisePersonalRecords) -> ProximityCue? {
        // Weight first — the more celebrated record.
        if let best = records.heaviestEntry,
           let bestWeight = best.weight,
           let usual = records.usualWeightRange,
           let unit = records.usualWeightUnit,
           unit == best.weightUnit {
            let bestDisplay = displayWeight(for: best)
            let delta = bestDisplay - usual.upperBound
            let threshold = max(bestDisplay * proximityWeightFraction, unit == .kg ? 2.5 : 5.0)
            if delta > 0, delta <= threshold, bestWeight > 0 {
                let formatted = Formatters.weight.string(from: NSNumber(value: delta)) ?? "\(delta)"
                return .weight(deltaText: "\(formatted) \(unit.symbol)")
            }
        }

        if let bestReps = records.mostRepsEntry?.reps,
           let usualReps = records.usualRepsRange {
            let delta = bestReps - usualReps.upperBound
            if delta > 0, delta <= proximityRepWindow {
                return .reps(delta: delta)
            }
        }

        return nil
    }

    /// The best entry's weight in the same display terms as the usual range
    /// (per-hand for dumbbell pairs).
    private static func displayWeight(for entry: SetEntry) -> Double {
        entry.exercise.displayedWeightInput(from: entry.weight) ?? (entry.weight ?? 0)
    }

    // MARK: - Ordering helpers

    private static func isChronologicallyBefore(_ lhs: SetEntry, _ rhs: SetEntry) -> Bool {
        if lhs.performedAt != rhs.performedAt { return lhs.performedAt < rhs.performedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func heaviestIsLessThan(_ lhs: SetEntry, _ rhs: SetEntry) -> Bool {
        let lk = kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let rk = kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(lk - rk) > weightEpsilon { return lk < rk }
        if (lhs.reps ?? 0) != (rhs.reps ?? 0) { return (lhs.reps ?? 0) < (rhs.reps ?? 0) }
        return lhs.performedAt < rhs.performedAt
    }

    private static func mostRepsIsLessThan(_ lhs: SetEntry, _ rhs: SetEntry) -> Bool {
        let lr = lhs.reps ?? 0
        let rr = rhs.reps ?? 0
        if lr != rr { return lr < rr }
        let lk = kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let rk = kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(lk - rk) > weightEpsilon { return lk < rk }
        return lhs.performedAt < rhs.performedAt
    }

    private static func dominantWeightUnit(in entries: [SetEntry]) -> WeightUnit? {
        guard !entries.isEmpty else { return nil }
        let counts = Dictionary(grouping: entries, by: { $0.weightUnit }).mapValues { $0.count }
        // Most common; tie-break toward the most recent entry's unit.
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key == entries.first?.weightUnit ? true : false
        }?.key
    }
}
