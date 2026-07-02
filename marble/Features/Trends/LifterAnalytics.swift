import Foundation

/// Pure computations behind the lifter-focused Trends sections: estimated
/// one-rep-max progression, per-muscle-group set counts, and rep-range
/// distribution. Everything here is derived from logged sets only — no schema
/// additions — and stays free of UI so the math is unit-testable.
enum LifterAnalytics {
    // MARK: - Estimated one-rep max

    /// A day's best estimated 1RM for one exercise.
    struct OneRepMaxPoint: Identifiable, Equatable {
        let date: Date
        /// Unit-agnostic value used for comparisons and the chart's Y axis.
        let kilograms: Double
        /// The same value converted into the series' display unit.
        let displayValue: Double
        /// The set that produced it, e.g. "225 lb × 5".
        let bestSetSummary: String

        var id: Date { date }
    }

    struct OneRepMaxSeries: Equatable {
        let points: [OneRepMaxPoint]
        let best: OneRepMaxPoint?
        let displayUnit: WeightUnit
    }

    /// Sets with more than this many reps are excluded from e1RM entirely —
    /// the standard formulas degrade badly past ~10–12 reps, and the major
    /// trackers cut off at 12 rather than clamp.
    static let oneRepMaxRepCap = 12

    /// Epley estimate, unit-normalized to kilograms. Deliberately NOT
    /// RPE-adjusted: `difficulty` defaults to 8 in this app, so an RPE
    /// adjustment would silently inflate every estimate for users who never
    /// touch the dial. Returns nil for rep counts outside the valid window.
    static func estimatedOneRepMaxKilograms(weight: Double, unit: WeightUnit, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= oneRepMaxRepCap else { return nil }
        let kilograms = PersonalRecords.kilograms(weight, unit: unit)
        return kilograms * (1.0 + Double(reps) / 30.0)
    }

    /// Per-day best e1RM for the given exercise, oldest first. Entries must
    /// already be range-filtered; this filters to the exercise and to sets the
    /// formula is valid for. Returns nil when the exercise doesn't track
    /// weight + reps or nothing qualifies.
    static func oneRepMaxSeries(
        entries: [SetEntry],
        exercise: Exercise,
        calendar: Calendar = .current
    ) -> OneRepMaxSeries? {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return nil }

        struct Candidate {
            let entry: SetEntry
            let kilograms: Double
        }

        var candidates: [Candidate] = []
        var displayUnit: WeightUnit?
        var latestPerformedAt = Date.distantPast

        for entry in entries where entry.exercise.id == exercise.id {
            guard
                let weight = entry.weight,
                let reps = entry.reps,
                let estimate = estimatedOneRepMaxKilograms(weight: weight, unit: entry.weightUnit, reps: reps)
            else { continue }
            candidates.append(Candidate(entry: entry, kilograms: estimate))
            // Display in whatever unit the lifter used most recently.
            if entry.performedAt >= latestPerformedAt {
                latestPerformedAt = entry.performedAt
                displayUnit = entry.weightUnit
            }
        }

        guard !candidates.isEmpty, let displayUnit else { return nil }

        let grouped = Dictionary(grouping: candidates) { candidate in
            calendar.startOfDay(for: candidate.entry.performedAt)
        }

        let points: [OneRepMaxPoint] = grouped.keys.sorted().compactMap { day in
            guard let best = grouped[day]?.max(by: { $0.kilograms < $1.kilograms }) else { return nil }
            let weightText = best.entry.exercise.formattedWeightSummary(
                best.entry.weight ?? 0,
                unit: best.entry.weightUnit
            )
            return OneRepMaxPoint(
                date: day,
                kilograms: best.kilograms,
                displayValue: displayWeight(fromKilograms: best.kilograms, in: displayUnit),
                bestSetSummary: "\(weightText) \u{00D7} \(best.entry.reps ?? 0)"
            )
        }

        guard !points.isEmpty else { return nil }
        return OneRepMaxSeries(
            points: points,
            best: points.max(by: { $0.kilograms < $1.kilograms }),
            displayUnit: displayUnit
        )
    }

    /// Kilograms → the display unit (inverse of `PersonalRecords.kilograms`).
    static func displayWeight(fromKilograms kilograms: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kg:
            return kilograms
        case .lb:
            return kilograms / 0.45359237
        }
    }

    // MARK: - Sets per muscle group

    struct MuscleGroupSets: Identifiable, Equatable {
        let category: ExerciseCategory
        let setCount: Int
        /// Sets per week averaged over the range; nil when the range is too
        /// short for a weekly average to mean anything (under two weeks).
        let averagePerWeek: Double?

        var id: ExerciseCategory { category }
    }

    /// The categories that represent actual muscle groups; activity buckets
    /// (run, power, bar, recover, other) don't belong on a volume chart.
    static let muscleGroupCategories: [ExerciseCategory] = [
        .chest, .back, .shoulders, .biceps, .triceps,
        .core, .quads, .hamstrings, .calves, .legs
    ]

    /// Set counts per muscle group across the (already range-filtered)
    /// entries, largest first. `weekCount` — how many weeks the range spans —
    /// enables the per-week average bodybuilders steer volume with (the
    /// 10–20-hard-sets-per-week heuristic); pass nil to omit averages.
    static func muscleGroupSets(entries: [SetEntry], weekCount: Double?) -> [MuscleGroupSets] {
        let allowed = Set(muscleGroupCategories)
        var counts: [ExerciseCategory: Int] = [:]
        for entry in entries {
            let category = entry.exercise.category
            guard allowed.contains(category) else { continue }
            counts[category, default: 0] += 1
        }
        return counts
            .map { category, count in
                MuscleGroupSets(
                    category: category,
                    setCount: count,
                    averagePerWeek: weekCount.flatMap { weeks in
                        weeks >= 2 ? Double(count) / weeks : nil
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.setCount == rhs.setCount {
                    return lhs.category.displayName < rhs.category.displayName
                }
                return lhs.setCount > rhs.setCount
            }
    }

    /// How many weeks a range spans, for per-week averaging. For `.all`, the
    /// span is measured from the earliest entry; short spans clamp to 1.
    static func weekCount(
        range: TrendRange,
        entries: [SetEntry],
        now: Date
    ) -> Double? {
        if let startDate = range.startDate {
            return max(1, now.timeIntervalSince(startDate) / 604_800)
        }
        guard let earliest = entries.map(\.performedAt).min() else { return nil }
        return max(1, now.timeIntervalSince(earliest) / 604_800)
    }

    // MARK: - Rep-range distribution

    enum RepRangeBucketKind: String, CaseIterable, Identifiable {
        case strength
        case hypertrophy
        case endurance

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strength: return "1–5 reps"
            case .hypertrophy: return "6–12 reps"
            case .endurance: return "13+ reps"
            }
        }

        /// Neutral framing on purpose: ranges describe how someone trains,
        /// they aren't a judgment (all ranges build muscle when sets are hard).
        var subtitle: String {
            switch self {
            case .strength: return "Strength"
            case .hypertrophy: return "Hypertrophy"
            case .endurance: return "Endurance"
            }
        }

        func contains(_ reps: Int) -> Bool {
            switch self {
            case .strength: return (1...5).contains(reps)
            case .hypertrophy: return (6...12).contains(reps)
            case .endurance: return reps >= 13
            }
        }
    }

    struct RepRangeBucket: Identifiable, Equatable {
        let kind: RepRangeBucketKind
        let setCount: Int
        /// 0…1 share of all counted sets.
        let share: Double

        var id: RepRangeBucketKind { kind }
    }

    /// Distribution of (already range- and exercise-filtered) sets across the
    /// classic rep buckets. Returns an empty array when no sets have reps, so
    /// the section can hide entirely.
    static func repRangeDistribution(entries: [SetEntry]) -> [RepRangeBucket] {
        let reps = entries.compactMap(\.reps).filter { $0 >= 1 }
        guard !reps.isEmpty else { return [] }
        let total = Double(reps.count)
        return RepRangeBucketKind.allCases.map { kind in
            let count = reps.filter { kind.contains($0) }.count
            return RepRangeBucket(kind: kind, setCount: count, share: Double(count) / total)
        }
    }
}
