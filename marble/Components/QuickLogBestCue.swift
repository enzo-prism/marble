import Foundation

/// Compact, preformatted personal-best context for the Journal's Log Again card.
///
/// This intentionally stays separate from `PersonalRecordBadge`: badges celebrate the set
/// that established a strength record, while this cue quietly shows the current all-time bar
/// to beat and also supports comparable-distance run times.
struct QuickLogBestCue: Equatable {
    let title: String
    let value: String
    let accessibilityLabel: String

    var text: String { "\(title) · \(value)" }
}

/// Pure linear-time derivation over the Journal's already-fetched history.
enum QuickLogBestCueResolver {
    /// Allows small GPS drift without treating materially different run distances as the
    /// same event (25 m at 5 km). The 1 m floor keeps short sprint comparisons practical.
    static let runDistanceToleranceFraction = 0.005

    static func resolve(latest: SetEntry, entries: [SetEntry]) -> QuickLogBestCue? {
        let metrics = latest.exercise.metrics
        let matchingEntries = entries.filter { $0.exercise.id == latest.exercise.id }

        if metrics.usesDistance,
           metrics.usesDuration,
           !metrics.usesWeight,
           !metrics.usesReps,
           let cue = bestRunTime(latest: latest, entries: matchingEntries) {
            return cue
        }

        if metrics.weightIsRequired,
           let cue = bestWeight(exercise: latest.exercise, entries: matchingEntries) {
            return cue
        }

        // Reps are the meaningful record for bodyweight, weighted-bodyweight, and
        // plyometric exercises. Optional added load must not change that classification.
        if metrics.usesReps,
           let cue = mostReps(entries: matchingEntries) {
            return cue
        }

        // Sensible fallback for custom weight-only profiles.
        if metrics.usesWeight {
            return bestWeight(exercise: latest.exercise, entries: matchingEntries)
        }

        // Duration-only activities (planks, hangs, sauna) deliberately show no cue: shorter
        // is not inherently better, so calling either extreme a universal "best" misleads.
        return nil
    }

    private static func bestWeight(exercise: Exercise, entries: [SetEntry]) -> QuickLogBestCue? {
        let best = entries.reduce(nil as SetEntry?) { current, candidate in
            guard let weight = candidate.weight, weight > 0 else { return current }
            guard let current else { return candidate }
            return weightEntry(candidate, isBetterThan: current) ? candidate : current
        }
        guard let best, let storedWeight = best.weight else { return nil }

        let displayedWeight = exercise.displayedWeightInput(from: storedWeight) ?? storedWeight
        let number = Formatters.weight.string(from: NSNumber(value: displayedWeight)) ?? "\(displayedWeight)"
        let suffix = exercise.resistanceTrackingStyle == .singleDumbbellPair ? " each" : ""
        let value = "\(number) \(best.weightUnit.symbol)\(suffix)"
        return QuickLogBestCue(
            title: "Best weight",
            value: value,
            accessibilityLabel: "Best weight, \(value)"
        )
    }

    private static func mostReps(entries: [SetEntry]) -> QuickLogBestCue? {
        let best = entries.reduce(nil as SetEntry?) { current, candidate in
            guard let reps = candidate.reps, reps > 0 else { return current }
            guard let current else { return candidate }
            return repsEntry(candidate, isBetterThan: current) ? candidate : current
        }
        guard let reps = best?.reps else { return nil }
        let value = reps == 1 ? "1 rep" : "\(reps) reps"
        return QuickLogBestCue(
            title: "Most reps",
            value: "\(reps)",
            accessibilityLabel: "Most reps, \(value)"
        )
    }

    private static func bestRunTime(latest: SetEntry, entries: [SetEntry]) -> QuickLogBestCue? {
        guard let distance = latest.distance, distance > 0 else { return nil }
        let targetMeters = latest.distanceUnit.meters(from: distance)
        let tolerance = max(1, targetMeters * runDistanceToleranceFraction)

        let best = entries.reduce(nil as SetEntry?) { current, candidate in
            guard let candidateDistance = candidate.distance,
                  candidateDistance > 0,
                  let duration = candidate.durationSeconds,
                  duration > 0
            else { return current }

            let candidateMeters = candidate.distanceUnit.meters(from: candidateDistance)
            guard abs(candidateMeters - targetMeters) <= tolerance else { return current }
            guard let current else { return candidate }
            return runEntry(candidate, isBetterThan: current) ? candidate : current
        }

        guard let duration = best?.durationSeconds else { return nil }
        let time = DateHelper.formattedClockDuration(seconds: duration)
        let distanceText = latest.exercise.formattedDistanceSummary(distance, unit: latest.distanceUnit)
        return QuickLogBestCue(
            title: "Best time",
            value: "\(time) for \(distanceText)",
            accessibilityLabel: "Best time for \(distanceText), \(spokenDuration(seconds: duration))"
        )
    }

    /// VoiceOver should announce unambiguous units: the compact visual `m` can mean either
    /// minutes or meters when it follows a run distance.
    private static func spokenDuration(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        var parts: [String] = []

        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if remainingSeconds > 0 || parts.isEmpty {
            parts.append("\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")")
        }
        return parts.joined(separator: " ")
    }

    private static func weightEntry(_ lhs: SetEntry, isBetterThan rhs: SetEntry) -> Bool {
        let lhsWeight = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let rhsWeight = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(lhsWeight - rhsWeight) > PersonalRecords.weightEpsilon {
            return lhsWeight > rhsWeight
        }
        if (lhs.reps ?? 0) != (rhs.reps ?? 0) {
            return (lhs.reps ?? 0) > (rhs.reps ?? 0)
        }
        return isLater(lhs, than: rhs)
    }

    private static func repsEntry(_ lhs: SetEntry, isBetterThan rhs: SetEntry) -> Bool {
        if (lhs.reps ?? 0) != (rhs.reps ?? 0) {
            return (lhs.reps ?? 0) > (rhs.reps ?? 0)
        }
        let lhsWeight = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
        let rhsWeight = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
        if abs(lhsWeight - rhsWeight) > PersonalRecords.weightEpsilon {
            return lhsWeight > rhsWeight
        }
        return isLater(lhs, than: rhs)
    }

    private static func runEntry(_ lhs: SetEntry, isBetterThan rhs: SetEntry) -> Bool {
        let lhsDuration = lhs.durationSeconds ?? .max
        let rhsDuration = rhs.durationSeconds ?? .max
        if lhsDuration != rhsDuration {
            return lhsDuration < rhsDuration
        }
        return isLater(lhs, than: rhs)
    }

    private static func isLater(_ lhs: SetEntry, than rhs: SetEntry) -> Bool {
        if lhs.performedAt != rhs.performedAt { return lhs.performedAt > rhs.performedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
