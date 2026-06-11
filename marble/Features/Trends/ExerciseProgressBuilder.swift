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

        return grouped.keys.sorted().compactMap { day in
            guard let dayEntries = grouped[day],
                  let best = bestSet(in: dayEntries, metric: metric) else {
                return nil
            }
            return ExerciseProgressPoint(
                date: day,
                score: best.score,
                bestSetSummary: best.bestSetSummary,
                scoreSummary: best.scoreSummary,
                entry: best.entry
            )
        }
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

        let heaviestEntry = filtered
            .filter { $0.weight != nil }
            .max { lhs, rhs in
                let lhsWeight = lhs.weight ?? 0
                let rhsWeight = rhs.weight ?? 0
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
                    return (lhs.weight ?? 0) < (rhs.weight ?? 0)
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

    private static func weightedBestSet(for entry: SetEntry) -> BestSet? {
        guard let weight = entry.weight else { return nil }
        let weightText = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
        if let reps = entry.reps {
            let bestSetSummary = "\(weightText) \(timesSymbol) \(reps)"
            let scoreSummary = "\(reps) reps"
            return BestSet(entry: entry, score: weight, bestSetSummary: bestSetSummary, scoreSummary: scoreSummary)
        }
        return BestSet(entry: entry, score: weight, bestSetSummary: weightText, scoreSummary: nil)
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
