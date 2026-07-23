import Foundation

/// A local wall-clock window for the screenshottable Daily Highlights card.
///
/// `endMinute` is the final visible minute, so the default `20:00...23:59`
/// becomes a half-open Date interval ending at the next local midnight. This
/// avoids hard-coded 23:59:59 values and stays correct across DST transitions.
struct DailyHighlightWindow: Equatable {
    static let defaultStartMinute = 20 * 60
    static let defaultEndMinute = 23 * 60 + 59

    let startMinute: Int
    let endMinute: Int

    var isValid: Bool {
        Self.validMinuteRange.contains(startMinute)
            && Self.validMinuteRange.contains(endMinute)
            && startMinute != endMinute
    }

    var crossesMidnight: Bool { endMinute < startMinute }

    func occurrence(containing now: Date, calendar: Calendar = .autoupdatingCurrent) -> DailyHighlightOccurrence? {
        guard isValid else { return nil }

        let today = calendar.startOfDay(for: now)
        if let occurrence = occurrence(anchoredTo: today, calendar: calendar), occurrence.contains(now) {
            return occurrence
        }

        guard crossesMidnight,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let occurrence = occurrence(anchoredTo: yesterday, calendar: calendar),
              occurrence.contains(now)
        else { return nil }
        return occurrence
    }

    private func occurrence(anchoredTo day: Date, calendar: Calendar) -> DailyHighlightOccurrence? {
        guard let start = Self.date(
            atMinute: startMinute,
            on: day,
            calendar: calendar,
            repeatedTimePolicy: .first
        ) else { return nil }

        let endDay: Date
        if crossesMidnight {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            endDay = nextDay
        } else {
            endDay = day
        }

        guard let finalVisibleMinute = Self.date(
            atMinute: endMinute,
            on: endDay,
            calendar: calendar,
            repeatedTimePolicy: .last
        ),
        let end = calendar.date(byAdding: .minute, value: 1, to: finalVisibleMinute),
        start < end
        else { return nil }

        return DailyHighlightOccurrence(
            celebrationDay: day,
            interval: DateInterval(start: start, end: end)
        )
    }

    private static func date(
        atMinute minute: Int,
        on day: Date,
        calendar: Calendar,
        repeatedTimePolicy: Calendar.RepeatedTimePolicy
    ) -> Date? {
        calendar.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: repeatedTimePolicy,
            direction: .forward
        )
    }

    private static let validMinuteRange = 0...(24 * 60 - 1)
}

struct DailyHighlightOccurrence: Equatable {
    let celebrationDay: Date
    let interval: DateInterval

    func contains(_ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}

struct DailyHighlightSummary: Equatable, Identifiable {
    struct Stat: Equatable, Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    let day: Date
    let headline: String
    let achievements: [DailyHighlightAchievement]
    let stats: [Stat]
    let setCount: Int
    let exerciseCount: Int
    let personalRecordCount: Int

    var id: Date { day }

}

struct DailyHighlightAchievement: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case personalRecord
        case runBest
        case liftProgress
        case dailyBest

        var systemImage: String {
            switch self {
            case .personalRecord: return "trophy.fill"
            case .runBest: return "figure.run"
            case .liftProgress: return "arrow.up.right"
            case .dailyBest: return "checkmark"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let value: String
    let detail: String
    let accessibilityLabel: String
}

/// Pure, deterministic derivation of one day's celebration from existing logs.
/// Nothing is persisted, uploaded, or inferred from notes/body measurements.
enum DailyHighlightsBuilder {
    static let runDistanceToleranceFraction = 0.005
    static let meaningfulStrengthGainFraction = 0.02
    static let maximumAchievements = 3

    static func build(
        history: [SetEntry],
        occurrence: DailyHighlightOccurrence,
        now: Date,
        displayWeightUnit: WeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DailyHighlightSummary? {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: occurrence.celebrationDay) else {
            return nil
        }

        // When the celebration belongs to today, do not let a future-dated log leak
        // into the card. Overnight windows after midnight may show the complete prior day.
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.isDate(occurrence.celebrationDay, inSameDayAs: today) ? min(now, dayEnd) : dayEnd
        let dayEntries = history.filter {
            $0.performedAt >= occurrence.celebrationDay
                && $0.performedAt < dayEnd
                && $0.performedAt <= cutoff
                && isValidTrainingEntry($0)
        }
        guard !dayEntries.isEmpty else { return nil }

        let priorEntries = history.filter { $0.performedAt < occurrence.celebrationDay }
        let groupedToday = Dictionary(grouping: dayEntries) { $0.exercise.id }
        let groupedPrior = Dictionary(grouping: priorEntries) { $0.exercise.id }

        var candidates: [Candidate] = []
        for (exerciseID, todaysEntries) in groupedToday {
            guard let exercise = todaysEntries.first?.exercise else { continue }
            let prior = groupedPrior[exerciseID] ?? []

            if let record = strengthRecordCandidate(
                exercise: exercise,
                today: todaysEntries,
                prior: prior
            ) {
                candidates.append(record)
                continue
            }

            if let run = runBestCandidate(exercise: exercise, today: todaysEntries, prior: prior) {
                candidates.append(run)
                continue
            }

            if let progress = liftProgressCandidate(
                exercise: exercise,
                today: todaysEntries,
                prior: prior,
                calendar: calendar
            ) {
                candidates.append(progress)
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if abs(lhs.magnitude - rhs.magnitude) > 0.000_001 { return lhs.magnitude > rhs.magnitude }
            if lhs.eventDate != rhs.eventDate { return lhs.eventDate > rhs.eventDate }
            if lhs.exerciseName != rhs.exerciseName { return lhs.exerciseName < rhs.exerciseName }
            return lhs.tieBreaker < rhs.tieBreaker
        }
        var achievements = Array(candidates.prefix(maximumAchievements).map(\.achievement))
        if achievements.isEmpty, let fallback = dailyBest(in: dayEntries) {
            achievements = [fallback]
        }

        let personalRecordCount = candidates.filter { $0.isPersonalRecord }.count
        let headline: String
        if !candidates.isEmpty, candidates.allSatisfy({ $0.achievement.kind == .runBest }) {
            headline = "A faster day."
        } else if personalRecordCount > 0 {
            headline = "You moved forward."
        } else if candidates.contains(where: { $0.achievement.kind == .liftProgress }) {
            headline = "Progress showed up."
        } else {
            headline = "You showed up."
        }

        let exerciseCount = Set(dayEntries.map { $0.exercise.id }).count
        return DailyHighlightSummary(
            day: occurrence.celebrationDay,
            headline: headline,
            achievements: achievements,
            stats: makeStats(
                entries: dayEntries,
                exerciseCount: exerciseCount,
                displayWeightUnit: displayWeightUnit
            ),
            setCount: dayEntries.count,
            exerciseCount: exerciseCount,
            personalRecordCount: personalRecordCount
        )
    }

    private struct Candidate {
        let achievement: DailyHighlightAchievement
        let priority: Int
        let magnitude: Double
        let eventDate: Date
        let exerciseName: String
        let tieBreaker: String
        let isPersonalRecord: Bool

    }

    private static func strengthRecordCandidate(
        exercise: Exercise,
        today: [SetEntry],
        prior: [SetEntry]
    ) -> Candidate? {
        let metrics = exercise.metrics
        guard metrics.usesWeight || metrics.usesReps, !prior.isEmpty else { return nil }

        let priorWeight = prior.compactMap { entry -> Double? in
            guard let weight = entry.weight, weight > 0 else { return nil }
            return PersonalRecords.kilograms(weight, unit: entry.weightUnit)
        }.max()
        let bestWeightEntry = today
            .filter { ($0.weight ?? 0) > 0 }
            .max { lhs, rhs in
                PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
                    < PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
            }
        let bestWeightKilograms = bestWeightEntry.flatMap { entry in
            entry.weight.map { PersonalRecords.kilograms($0, unit: entry.weightUnit) }
        }
        let isWeightRecord: Bool
        if metrics.usesWeight,
           let priorWeight,
           let bestWeightKilograms {
            isWeightRecord = bestWeightKilograms > priorWeight + PersonalRecords.weightEpsilon
        } else {
            isWeightRecord = false
        }

        let priorReps = prior.compactMap(\.reps).filter { $0 > 0 }.max()
        let bestRepsEntry = today.filter { ($0.reps ?? 0) > 0 }.max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        let bestReps = bestRepsEntry?.reps
        let isRepsRecord: Bool
        if metrics.usesReps,
           let priorReps,
           let bestReps {
            isRepsRecord = bestReps > priorReps
        } else {
            isRepsRecord = false
        }

        guard isWeightRecord || isRepsRecord else { return nil }
        let representative: SetEntry
        if isWeightRecord, isRepsRecord,
           bestWeightEntry?.id == bestRepsEntry?.id,
           let combined = bestWeightEntry {
            representative = combined
        } else if isWeightRecord, let bestWeightEntry {
            representative = bestWeightEntry
        } else if let bestRepsEntry {
            representative = bestRepsEntry
        } else {
            return nil
        }

        let isCombinedRecord = isWeightRecord
            && isRepsRecord
            && bestWeightEntry?.id == bestRepsEntry?.id
        let detail: String
        if isCombinedRecord {
            detail = "New weight + rep best"
        } else if isWeightRecord {
            detail = "New weight best"
        } else {
            detail = "New rep best"
        }

        let weightMagnitude: Double
        if let bestWeightKilograms, let priorWeight {
            weightMagnitude = (bestWeightKilograms - priorWeight) / max(priorWeight, 0.000_001)
        } else {
            weightMagnitude = 0
        }
        let repsMagnitude: Double
        if let bestReps, let priorReps {
            repsMagnitude = Double(bestReps - priorReps) / Double(max(priorReps, 1))
        } else {
            repsMagnitude = 0
        }
        let value = setSummary(for: representative)
        return Candidate(
            achievement: DailyHighlightAchievement(
                id: "\(exercise.id.uuidString)-personal-record",
                kind: .personalRecord,
                title: exercise.name,
                value: value,
                detail: detail,
                accessibilityLabel: "\(exercise.name), \(detail.lowercased()), \(spokenSetSummary(for: representative))"
            ),
            priority: 0,
            magnitude: max(weightMagnitude, repsMagnitude),
            eventDate: representative.performedAt,
            exerciseName: exercise.name,
            tieBreaker: representative.id.uuidString,
            isPersonalRecord: true
        )
    }

    private static func runBestCandidate(
        exercise: Exercise,
        today: [SetEntry],
        prior: [SetEntry]
    ) -> Candidate? {
        let metrics = exercise.metrics
        guard metrics.usesDistance, metrics.usesDuration, !metrics.usesWeight, !metrics.usesReps else {
            return nil
        }

        var best: (entry: SetEntry, priorDuration: Int, improvement: Double)?
        for entry in today {
            guard let distance = entry.distance, distance > 0,
                  let duration = entry.durationSeconds, duration > 0 else { continue }
            let meters = entry.distanceUnit.meters(from: distance)
            let tolerance = max(1, meters * runDistanceToleranceFraction)
            let previousDuration = prior.compactMap { candidate -> Int? in
                guard let candidateDistance = candidate.distance, candidateDistance > 0,
                      let candidateDuration = candidate.durationSeconds, candidateDuration > 0 else { return nil }
                let candidateMeters = candidate.distanceUnit.meters(from: candidateDistance)
                return abs(candidateMeters - meters) <= tolerance ? candidateDuration : nil
            }.min()
            guard let previousDuration, duration < previousDuration else { continue }
            let improvement = Double(previousDuration - duration) / Double(previousDuration)
            if best == nil || improvement > best!.improvement {
                best = (entry, previousDuration, improvement)
            }
        }
        guard let best, let distance = best.entry.distance, let duration = best.entry.durationSeconds else { return nil }

        let distanceText = exercise.formattedDistanceSummary(distance, unit: best.entry.distanceUnit)
        let timeText = DateHelper.formattedClockDuration(seconds: duration)
        let secondsFaster = best.priorDuration - duration
        let detail = secondsFaster == 1 ? "1 second faster · new best" : "\(secondsFaster) seconds faster · new best"
        return Candidate(
            achievement: DailyHighlightAchievement(
                id: "\(exercise.id.uuidString)-run-best",
                kind: .runBest,
                title: exercise.name,
                value: "\(timeText) for \(distanceText)",
                detail: detail,
                accessibilityLabel: "\(exercise.name), new time best for \(distanceText), \(spokenDuration(duration)), \(detail)"
            ),
            priority: 1,
            magnitude: best.improvement,
            eventDate: best.entry.performedAt,
            exerciseName: exercise.name,
            tieBreaker: best.entry.id.uuidString,
            isPersonalRecord: true
        )
    }

    private static func liftProgressCandidate(
        exercise: Exercise,
        today: [SetEntry],
        prior: [SetEntry],
        calendar: Calendar
    ) -> Candidate? {
        guard exercise.metrics.usesWeight, exercise.metrics.usesReps else { return nil }
        let todayEstimates = today.compactMap { entry -> (SetEntry, Double)? in
            guard let weight = entry.weight, let reps = entry.reps,
                  let estimate = LifterAnalytics.estimatedOneRepMaxKilograms(
                    weight: weight,
                    unit: entry.weightUnit,
                    reps: reps
                  ) else { return nil }
            return (entry, estimate)
        }
        guard let todayBest = todayEstimates.max(by: { $0.1 < $1.1 }) else { return nil }

        let priorDays = Dictionary(grouping: prior) { calendar.startOfDay(for: $0.performedAt) }
        guard let previousDay = priorDays.keys.max(), let previousEntries = priorDays[previousDay] else { return nil }
        let previousBest = previousEntries.compactMap { entry -> Double? in
            guard let weight = entry.weight, let reps = entry.reps else { return nil }
            return LifterAnalytics.estimatedOneRepMaxKilograms(weight: weight, unit: entry.weightUnit, reps: reps)
        }.max()
        guard let previousBest, previousBest > 0 else { return nil }

        let gain = (todayBest.1 - previousBest) / previousBest
        guard gain >= meaningfulStrengthGainFraction else { return nil }
        let percent = Int((gain * 100).rounded())
        return Candidate(
            achievement: DailyHighlightAchievement(
                id: "\(exercise.id.uuidString)-lift-progress",
                kind: .liftProgress,
                title: exercise.name,
                value: "+\(percent)%",
                detail: "Estimated strength vs last session",
                accessibilityLabel: "\(exercise.name), estimated strength up \(percent) percent versus last session"
            ),
            priority: 2,
            magnitude: gain,
            eventDate: todayBest.0.performedAt,
            exerciseName: exercise.name,
            tieBreaker: todayBest.0.id.uuidString,
            isPersonalRecord: false
        )
    }

    private static func dailyBest(in entries: [SetEntry]) -> DailyHighlightAchievement? {
        guard let best = entries.max(by: { lhs, rhs in
            let lhsWeight = PersonalRecords.kilograms(lhs.weight ?? 0, unit: lhs.weightUnit)
            let rhsWeight = PersonalRecords.kilograms(rhs.weight ?? 0, unit: rhs.weightUnit)
            if abs(lhsWeight - rhsWeight) > PersonalRecords.weightEpsilon { return lhsWeight < rhsWeight }
            if (lhs.reps ?? 0) != (rhs.reps ?? 0) { return (lhs.reps ?? 0) < (rhs.reps ?? 0) }
            let lhsDistance = lhs.distanceUnit.meters(from: lhs.distance ?? 0)
            let rhsDistance = rhs.distanceUnit.meters(from: rhs.distance ?? 0)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            if (lhs.durationSeconds ?? 0) != (rhs.durationSeconds ?? 0) {
                return (lhs.durationSeconds ?? 0) < (rhs.durationSeconds ?? 0)
            }
            return lhs.performedAt < rhs.performedAt
        }) else { return nil }
        return DailyHighlightAchievement(
            id: "\(best.exercise.id.uuidString)-daily-best",
            kind: .dailyBest,
            title: best.exercise.name,
            value: setSummary(for: best),
            detail: "Today's work",
            accessibilityLabel: "\(best.exercise.name), today's work, \(spokenSetSummary(for: best))"
        )
    }

    private static func makeStats(
        entries: [SetEntry],
        exerciseCount: Int,
        displayWeightUnit: WeightUnit
    ) -> [DailyHighlightSummary.Stat] {
        var stats = [
            DailyHighlightSummary.Stat(label: entries.count == 1 ? "set" : "sets", value: "\(entries.count)"),
            DailyHighlightSummary.Stat(label: exerciseCount == 1 ? "exercise" : "exercises", value: "\(exerciseCount)")
        ]

        let volumeKilograms = entries.reduce(0.0) { total, entry in
            guard let weight = entry.weight, weight > 0, let reps = entry.reps, reps > 0 else { return total }
            return total + PersonalRecords.kilograms(weight, unit: entry.weightUnit) * Double(reps)
        }
        if volumeKilograms > 0 {
            let displayVolume = LifterAnalytics.displayWeight(fromKilograms: volumeKilograms, in: displayWeightUnit)
            stats.append(DailyHighlightSummary.Stat(
                label: "volume",
                value: compactNumber(displayVolume, unit: displayWeightUnit.symbol)
            ))
            return stats
        }

        let distanceMeters = entries.reduce(0.0) { total, entry in
            guard let distance = entry.distance, distance > 0 else { return total }
            return total + entry.distanceUnit.meters(from: distance)
        }
        if distanceMeters > 0 {
            stats.append(DailyHighlightSummary.Stat(label: "covered", value: compactDistance(distanceMeters)))
            return stats
        }

        let reps = entries.compactMap(\.reps).filter { $0 > 0 }.reduce(0, +)
        if reps > 0 {
            stats.append(DailyHighlightSummary.Stat(label: "reps", value: "\(reps)"))
            return stats
        }

        let duration = entries.compactMap(\.durationSeconds).filter { $0 > 0 }.reduce(0, +)
        if duration > 0 {
            stats.append(DailyHighlightSummary.Stat(label: "active", value: DateHelper.formattedDuration(seconds: duration)))
        }
        return stats
    }

    private static func setSummary(for entry: SetEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weight, weight > 0 {
            var weightText = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if entry.exercise.resistanceTrackingStyle == .singleDumbbellPair,
               let range = weightText.range(of: " (") {
                weightText = String(weightText[..<range.lowerBound])
            }
            parts.append(weightText)
        }
        if let reps = entry.reps, reps > 0 {
            if parts.isEmpty {
                parts.append(reps == 1 ? "1 rep" : "\(reps) reps")
            } else {
                parts[parts.count - 1] += " × \(reps)"
            }
        }
        if let distance = entry.distance, distance > 0 {
            parts.append(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))
        }
        if let duration = entry.durationSeconds, duration > 0 {
            parts.append(DateHelper.formattedClockDuration(seconds: duration))
        }
        return parts.isEmpty ? "Logged today" : parts.joined(separator: " · ")
    }

    private static func spokenSetSummary(for entry: SetEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weight, weight > 0 {
            parts.append(entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit))
        }
        if let reps = entry.reps, reps > 0 {
            parts.append(reps == 1 ? "1 rep" : "\(reps) reps")
        }
        if let distance = entry.distance, distance > 0 {
            parts.append(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))
        }
        if let duration = entry.durationSeconds, duration > 0 {
            parts.append(spokenDuration(duration))
        }
        return parts.joined(separator: ", ")
    }

    private static func spokenDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if remaining > 0 || parts.isEmpty { parts.append("\(remaining) \(remaining == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }

    private static func compactNumber(_ value: Double, unit: String) -> String {
        let number: String
        if value >= 10_000 {
            number = String(format: "%.0fk", value / 1_000)
        } else if value >= 1_000 {
            number = String(format: "%.1fk", value / 1_000)
        } else {
            number = Formatters.weight.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        return "\(number) \(unit)"
    }

    private static func compactDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            let number = Formatters.distance.string(from: NSNumber(value: kilometers)) ?? String(format: "%.1f", kilometers)
            return "\(number) km"
        }
        let number = Formatters.distance.string(from: NSNumber(value: meters)) ?? String(format: "%.0f", meters)
        return "\(number) m"
    }

    private static func isValidTrainingEntry(_ entry: SetEntry) -> Bool {
        (entry.weight ?? 0) > 0
            || (entry.reps ?? 0) > 0
            || (entry.distance ?? 0) > 0
            || (entry.durationSeconds ?? 0) > 0
    }
}
