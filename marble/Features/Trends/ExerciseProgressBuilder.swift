import Foundation

struct ExerciseProgressPoint: Identifiable {
    let date: Date
    let score: Double
    let bestSetSummary: String
    let scoreSummary: String?
    let entry: SetEntry

    var id: Date { date }
}

struct ExerciseLiftBests {
    let exerciseName: String
    let heaviestEntry: SetEntry?
    let mostRepsEntry: SetEntry?

    var hasAnyBest: Bool {
        heaviestEntry != nil || mostRepsEntry != nil
    }
}

enum ExerciseProgressBuilder {
    static func buildPoints(
        entries: [SetEntry],
        exercise: Exercise,
        range: TrendRange,
        calendar: Calendar = .current
    ) -> [ExerciseProgressPoint] {
        let metric = progressMetric(for: exercise.metrics)
        let startDate = range.startDate
        let filtered = entries.filter { entry in
            guard entry.exercise.id == exercise.id else { return false }
            if let startDate {
                return entry.performedAt >= startDate
            }
            return true
        }

        let grouped = Dictionary(grouping: filtered) { entry in
            calendar.startOfDay(for: entry.performedAt)
        }

        // Weighted series are scored in kilograms so mixed lb/kg history compares
        // correctly. Plot them back in whatever unit the lifter used most recently,
        // so an all-lb user still reads their own numbers on the axis — the same
        // display contract LifterAnalytics.oneRepMaxSeries uses.
        let displayUnit = metric == .weighted ? latestWeightUnit(in: filtered) : nil

        return grouped.keys.sorted().compactMap { day in
            guard let dayEntries = grouped[day],
                  let best = bestSet(in: dayEntries, metric: metric) else {
                return nil
            }
            return ExerciseProgressPoint(
                date: day,
                score: displayScore(for: best, displayUnit: displayUnit),
                bestSetSummary: best.bestSetSummary,
                scoreSummary: best.scoreSummary,
                entry: best.entry
            )
        }
    }

    /// The kilogram-scored `best` expressed in `displayUnit`.
    ///
    /// Returns the logged weight verbatim when it was already recorded in the display
    /// unit — the overwhelmingly common single-unit case. Round-tripping it through
    /// kilograms is lossy (185 lb → kg → lb yields 185.00000000000003), and a lifter
    /// who logged 185 should get back exactly 185.
    private static func displayScore(for best: BestSet, displayUnit: WeightUnit?) -> Double {
        guard let displayUnit else { return best.score }
        if let weight = best.entry.weight, best.entry.weightUnit == displayUnit {
            return weight
        }
        return LifterAnalytics.displayWeight(fromKilograms: best.score, in: displayUnit)
    }

    /// The weight unit of the most recently performed set that actually has a weight.
    private static func latestWeightUnit(in entries: [SetEntry]) -> WeightUnit? {
        var unit: WeightUnit?
        var latest = Date.distantPast
        for entry in entries where entry.weight != nil {
            if entry.performedAt >= latest {
                latest = entry.performedAt
                unit = entry.weightUnit
            }
        }
        return unit
    }

    static func buildLiftBests(
        entries: [SetEntry],
        exercise: Exercise,
        range: TrendRange
    ) -> ExerciseLiftBests? {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return nil }

        let startDate = range.startDate
        let filtered = entries.filter { entry in
            guard entry.exercise.id == exercise.id else { return false }
            if let startDate {
                return entry.performedAt >= startDate
            }
            return true
        }

        // Compare in kilograms so a 100 kg set beats a 100 lb set — the same
        // unit-normalization PersonalRecords uses for the journal's PR badges.
        let heaviestEntry = filtered
            .filter { $0.weight != nil }
            .max { lhs, rhs in
                let lhsWeight = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
                let rhsWeight = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
                if lhsWeight == rhsWeight {
                    return (lhs.reps ?? 0) < (rhs.reps ?? 0)
                }
                return lhsWeight < rhsWeight
            }

        let mostRepsEntry = filtered
            .filter { $0.reps != nil }
            .max { lhs, rhs in
                let lhsReps = lhs.reps ?? 0
                let rhsReps = rhs.reps ?? 0
                if lhsReps == rhsReps {
                    return PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
                        < PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
                }
                return lhsReps < rhsReps
            }

        let bests = ExerciseLiftBests(
            exerciseName: exercise.name,
            heaviestEntry: heaviestEntry,
            mostRepsEntry: mostRepsEntry
        )
        return bests.hasAnyBest ? bests : nil
    }

    private static func progressMetric(for profile: ExerciseMetricsProfile) -> ExerciseProgressMetric {
        if profile.usesDistance && profile.usesDuration && !profile.usesWeight && !profile.usesReps {
            return .speed
        }
        if profile.usesDistance && !profile.usesWeight && !profile.usesReps {
            return .distance
        }
        if profile.usesDuration && !profile.usesWeight && !profile.usesReps {
            return .duration
        }
        if profile.weightIsRequired {
            return .weighted
        }
        if profile.usesReps {
            return .reps
        }
        if profile.usesDuration {
            return .duration
        }
        if profile.usesDistance {
            return .distance
        }
        if profile.usesWeight {
            return .weighted
        }
        return .reps
    }

    private static func bestSet(in entries: [SetEntry], metric: ExerciseProgressMetric) -> BestSet? {
        let candidates = entries.compactMap { entry in
            switch metric {
            case .weighted:
                return weightedBestSet(for: entry)
            case .reps:
                return repsBestSet(for: entry)
            case .distance:
                return distanceBestSet(for: entry)
            case .duration:
                return durationBestSet(for: entry)
            case .speed:
                return speedBestSet(for: entry)
            }
        }
        return candidates.max(by: { $0.score < $1.score })
    }

    /// Scores in **kilograms**, like `distanceBestSet` scores in meters. Raw weights
    /// can't be compared across units: 185 lb (83.9 kg) would outrank a 100 kg set,
    /// inverting both the day's "best set" and the chart's trend line. `buildPoints`
    /// converts the finished series back into the lifter's own unit for display.
    private static func weightedBestSet(for entry: SetEntry) -> BestSet? {
        guard let weight = entry.weight else { return nil }
        let kilograms = PersonalRecords.kilograms(weight, unit: entry.weightUnit)
        let weightText = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
        if let reps = entry.reps {
            let bestSetSummary = "\(weightText) \(timesSymbol) \(reps)"
            let scoreSummary = "\(reps) reps"
            return BestSet(entry: entry, score: kilograms, bestSetSummary: bestSetSummary, scoreSummary: scoreSummary)
        }
        return BestSet(entry: entry, score: kilograms, bestSetSummary: weightText, scoreSummary: nil)
    }

    private static func repsBestSet(for entry: SetEntry) -> BestSet? {
        guard let reps = entry.reps else { return nil }
        return BestSet(entry: entry, score: Double(reps), bestSetSummary: "\(reps) reps", scoreSummary: nil)
    }

    private static func distanceBestSet(for entry: SetEntry) -> BestSet? {
        guard let distance = entry.distance else { return nil }
        let meters = entry.distanceUnit.meters(from: distance)
        let summary = entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit)
        if let seconds = entry.durationSeconds, seconds > 0 {
            return BestSet(entry: entry, score: meters, bestSetSummary: "\(summary) in \(DateHelper.formattedClockDuration(seconds: seconds))", scoreSummary: nil)
        }
        return BestSet(entry: entry, score: meters, bestSetSummary: summary, scoreSummary: nil)
    }

    private static func durationBestSet(for entry: SetEntry) -> BestSet? {
        guard let seconds = entry.durationSeconds, seconds > 0 else { return nil }
        let summary = DateHelper.formattedClockDuration(seconds: seconds)
        return BestSet(entry: entry, score: Double(seconds), bestSetSummary: summary, scoreSummary: nil)
    }

    private static func speedBestSet(for entry: SetEntry) -> BestSet? {
        guard let distance = entry.distance,
              let seconds = entry.durationSeconds,
              seconds > 0 else {
            return nil
        }

        let metersPerSecond = entry.distanceUnit.meters(from: distance) / Double(seconds)
        let distanceSummary = entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit)
        return BestSet(
            entry: entry,
            score: metersPerSecond,
            bestSetSummary: "\(distanceSummary) in \(DateHelper.formattedClockDuration(seconds: seconds))",
            scoreSummary: Formatters.paceText(distance: distance, unit: entry.distanceUnit, durationSeconds: seconds)
        )
    }

    private static func formattedNumber(_ value: Double) -> String {
        Formatters.distance.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let timesSymbol = "\u{00D7}"
}

private enum ExerciseProgressMetric {
    case weighted
    case reps
    case distance
    case duration
    case speed
}

private struct BestSet {
    let entry: SetEntry
    let score: Double
    let bestSetSummary: String
    let scoreSummary: String?
}
