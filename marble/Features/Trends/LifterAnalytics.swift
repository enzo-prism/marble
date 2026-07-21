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

    // MARK: - Relative strength (DOTS)
    //
    // Added in 2.2 "Body". Everything below is additive: no existing analytic
    // changed shape, and every entry point returns nil/empty when there is no
    // bodyweight data, so the UI omits the metric rather than guessing.

    /// A bodyweight measurement reduced to what the math needs. Keeping the
    /// pure layer off `BodyMetricEntry` means the DOTS tests run without a
    /// `ModelContext`.
    struct BodyweightSample: Equatable {
        let date: Date
        /// Canonical kilograms (`BodyMetricEntry` stores nothing else).
        let kilograms: Double

        init(date: Date, kilograms: Double) {
            self.date = date
            self.kilograms = kilograms
        }

        init(_ entry: BodyMetricEntry) {
            self.date = entry.measuredAt
            self.kilograms = entry.weightKilograms
        }
    }

    /// How far a lift may reach for a bodyweight measurement. Beyond two weeks
    /// a lifter's weight has genuinely moved, and a stale denominator makes
    /// DOTS look like progress that never happened — so we omit the metric
    /// instead of interpolating.
    static let bodyweightLookupWindowDays = 14

    /// Nearest bodyweight to `date` within the window, or nil. Ties resolve to
    /// the more recent measurement so the result is deterministic regardless of
    /// input ordering.
    static func nearestBodyweight(
        to date: Date,
        in samples: [BodyweightSample],
        windowDays: Int = bodyweightLookupWindowDays
    ) -> BodyweightSample? {
        let window = Double(windowDays) * 86_400
        var best: BodyweightSample?
        var bestDistance = Double.greatestFiniteMagnitude

        for sample in samples {
            let distance = abs(sample.date.timeIntervalSince(date))
            guard distance <= window else { continue }
            if distance < bestDistance || (distance == bestDistance && sample.date > (best?.date ?? .distantPast)) {
                best = sample
                bestDistance = distance
            }
        }
        return best
    }

    // DOTS coefficients.
    //
    // Source: the DOTS ("Dynamic Objective Team Scoring") formula adopted by
    // the German powerlifting federation (BVDK) as the successor to Wilks,
    // derived by Tim Konertz. The five polynomial coefficients below are the
    // published values, matching the reference implementation in
    // OpenPowerlifting's `opl-data` (`modules/coefficients/src/dots.rs`) and
    // OpenLifter.
    //
    //   coefficient = 500 / (A·x⁴ + B·x³ + C·x² + D·x + E),  x = bodyweight kg
    //   DOTS        = total kg × coefficient
    //
    // The polynomial is only fitted over competitive bodyweight ranges, so the
    // reference implementations clamp x before evaluating; outside the clamp
    // the quartic turns over and produces nonsense. We clamp identically.
    private enum DotsCoefficients {
        static let male = (
            a: -0.000001093,
            b: 0.0007391293,
            c: -0.1918759221,
            d: 24.0900756,
            e: -307.75076
        )
        static let female = (
            a: -0.0000010706,
            b: 0.0007137536,
            c: -0.1955773591,
            d: 24.7275145,
            e: -57.96288
        )

        static let maleBodyweightClamp: ClosedRange<Double> = 40...210
        static let femaleBodyweightClamp: ClosedRange<Double> = 40...150
    }

    /// The DOTS score for a lift `totalKilograms` performed at
    /// `bodyweightKilograms`. Pure, unit-free of any display concern, and
    /// unit-tested against published reference values.
    ///
    /// Returns 0 for non-positive inputs rather than trapping — callers gate on
    /// the presence of bodyweight data, and a 0 reads as "no score" everywhere
    /// it could leak through.
    static func dots(totalKilograms: Double, bodyweightKilograms: Double, isFemale: Bool) -> Double {
        guard totalKilograms > 0, bodyweightKilograms > 0 else { return 0 }

        let coefficients = isFemale ? DotsCoefficients.female : DotsCoefficients.male
        let clamp = isFemale ? DotsCoefficients.femaleBodyweightClamp : DotsCoefficients.maleBodyweightClamp
        let x = min(max(bodyweightKilograms, clamp.lowerBound), clamp.upperBound)

        let denominator = coefficients.a * pow(x, 4)
            + coefficients.b * pow(x, 3)
            + coefficients.c * pow(x, 2)
            + coefficients.d * x
            + coefficients.e

        guard denominator > 0 else { return 0 }
        return totalKilograms * (500.0 / denominator)
    }

    /// One day's lift scored against the bodyweight nearest to it.
    struct RelativeStrengthPoint: Identifiable, Equatable {
        /// The training day the lift happened on.
        let date: Date
        let dots: Double
        /// The lift that was scored, in kilograms (an e1RM here, not a
        /// three-lift total — see `RelativeStrengthSummary`).
        let liftKilograms: Double
        let bodyweightKilograms: Double
        /// When that bodyweight was actually measured.
        let bodyweightMeasuredAt: Date
        /// Whole days between the lift and the bodyweight backing it, so the UI
        /// can be honest about a scored-against-stale-weight case.
        let bodyweightAgeDays: Int

        var id: Date { date }
    }

    /// DOTS across an e1RM series, plus its latest and best points.
    ///
    /// **Naming honesty:** DOTS was designed to score a powerlifting *total*.
    /// Marble applies the same scale to a single lift's estimated 1RM, which
    /// makes it a valid bodyweight-relative comparison of that lift over time —
    /// but not a competition DOTS total. The UI copy says so; do not relabel it
    /// as a total.
    struct RelativeStrengthSummary: Equatable {
        let points: [RelativeStrengthPoint]
        let latest: RelativeStrengthPoint?
        let best: RelativeStrengthPoint?
    }

    /// Scores each day of an e1RM series against the nearest bodyweight within
    /// `bodyweightLookupWindowDays`. Returns nil when no day can be scored, so
    /// the caller omits the line entirely rather than showing a partial or
    /// invented metric.
    static func relativeStrength(
        oneRepMax series: OneRepMaxSeries,
        bodyweights: [BodyweightSample],
        isFemale: Bool,
        windowDays: Int = bodyweightLookupWindowDays,
        calendar: Calendar = .current
    ) -> RelativeStrengthSummary? {
        guard !bodyweights.isEmpty else { return nil }

        var points: [RelativeStrengthPoint] = []
        points.reserveCapacity(series.points.count)

        for point in series.points {
            guard let sample = nearestBodyweight(to: point.date, in: bodyweights, windowDays: windowDays) else {
                continue
            }
            let score = dots(
                totalKilograms: point.kilograms,
                bodyweightKilograms: sample.kilograms,
                isFemale: isFemale
            )
            guard score > 0 else { continue }
            let ageDays = abs(calendar.dateComponents([.day], from: sample.date, to: point.date).day ?? 0)
            points.append(RelativeStrengthPoint(
                date: point.date,
                dots: score,
                liftKilograms: point.kilograms,
                bodyweightKilograms: sample.kilograms,
                bodyweightMeasuredAt: sample.date,
                bodyweightAgeDays: ageDays
            ))
        }

        guard !points.isEmpty else { return nil }
        return RelativeStrengthSummary(
            points: points,
            latest: points.max(by: { $0.date < $1.date }),
            best: points.max(by: { $0.dots < $1.dots })
        )
    }
}
