import Foundation

/// A single period-over-period change shown in the Trends momentum strip.
struct MomentumDelta: Identifiable {
    enum Direction {
        case up
        case down
        case flat
    }

    let title: String
    let valueText: String
    /// Fractional change vs the previous window (0.18 == +18%). `nil` when there is no baseline.
    let changeFraction: Double?
    /// `true` when the previous window was empty but this window has data.
    let isNew: Bool

    var id: String { title }

    var direction: Direction {
        if isNew { return .up }
        guard let changeFraction else { return .flat }
        if changeFraction > 0.005 { return .up }
        if changeFraction < -0.005 { return .down }
        return .flat
    }

    /// Short trailing descriptor such as "18%" or "New". `nil` when flat / no baseline.
    var changeText: String? {
        if isNew { return "New" }
        guard let changeFraction, direction != .flat else { return nil }
        let percent = Int((abs(changeFraction) * 100).rounded())
        guard percent > 0 else { return nil }
        return "\(percent)%"
    }

    var accessibilityText: String {
        switch direction {
        case .up:
            if isNew { return "\(title) \(valueText), new this period" }
            return changeText.map { "\(title) \(valueText), up \($0)" } ?? "\(title) \(valueText)"
        case .down:
            return changeText.map { "\(title) \(valueText), down \($0)" } ?? "\(title) \(valueText)"
        case .flat:
            return "\(title) \(valueText), unchanged"
        }
    }
}

/// An all-time record that was set recently enough to celebrate.
struct RecentPR {
    let metricTitle: String
    let valueText: String
    let exerciseName: String
    let date: Date

    var accessibilityText: String {
        "New personal record, \(metricTitle.lowercased()) \(valueText) for \(exerciseName)"
    }
}

struct MomentumSummary {
    let deltas: [MomentumDelta]
    /// Consecutive days (ending today/yesterday) with at least one logged set. See ``StreakBuilder``.
    let streakDays: Int
    let recentPR: RecentPR?

    var hasContent: Bool {
        deltas.contains(where: { $0.changeText != nil }) || streakDays >= StreakBuilder.minimumStreakDays || recentPR != nil
    }

    static let empty = MomentumSummary(deltas: [], streakDays: 0, recentPR: nil)
}

enum MomentumBuilder {
    static let recentPRWindowDays = 7

    /// - Parameter entries: set entries already scoped to the selected exercise (if any) but
    ///   **not** filtered by range — the builder needs the previous window and all-time data.
    static func build(
        entries: [SetEntry],
        range: TrendRange,
        exercise: Exercise?,
        now: Date = AppEnvironment.now,
        calendar: Calendar = .current
    ) -> MomentumSummary {
        MomentumSummary(
            deltas: buildDeltas(entries: entries, range: range, now: now, calendar: calendar),
            streakDays: StreakBuilder.currentStreak(entries: entries, now: now, calendar: calendar),
            recentPR: recentPR(entries: entries, now: now, calendar: calendar)
        )
    }

    // MARK: - Deltas

    private static func buildDeltas(
        entries: [SetEntry],
        range: TrendRange,
        now: Date,
        calendar: Calendar
    ) -> [MomentumDelta] {
        guard let dayCount = range.dayCount else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let currentStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -dayCount, to: currentStart) else {
            return []
        }

        let current = entries.filter { $0.performedAt >= currentStart }
        let previous = entries.filter { $0.performedAt >= previousStart && $0.performedAt < currentStart }

        var deltas: [MomentumDelta] = []

        if !current.isEmpty || !previous.isEmpty {
            deltas.append(makeDelta(
                title: "Sets",
                currentValue: Double(current.count),
                previousValue: Double(previous.count),
                valueText: "\(current.count)"
            ))
        }

        let currentVolume = totalVolumeScore(current)
        let previousVolume = totalVolumeScore(previous)
        if currentVolume > 0 || previousVolume > 0 {
            deltas.append(makeDelta(
                title: "Volume",
                currentValue: currentVolume,
                previousValue: previousVolume,
                valueText: Formatters.compactNumberText(currentVolume)
            ))
        }

        return deltas
    }

    private static func makeDelta(
        title: String,
        currentValue: Double,
        previousValue: Double,
        valueText: String
    ) -> MomentumDelta {
        let isNew = previousValue <= 0 && currentValue > 0
        let fraction: Double? = previousValue > 0 ? (currentValue - previousValue) / previousValue : nil
        return MomentumDelta(title: title, valueText: valueText, changeFraction: fraction, isNew: isNew)
    }

    /// Composite volume score consistent with `TrendWeeklySummary.totalVolumeScore`:
    /// weight×reps + bodyweight reps + minutes of duration.
    static func totalVolumeScore(_ entries: [SetEntry]) -> Double {
        var weighted = 0.0
        var reps = 0
        var durationSeconds = 0
        for entry in entries {
            if let weight = entry.weight, let entryReps = entry.reps {
                weighted += weight * Double(entryReps)
            } else if let entryReps = entry.reps {
                reps += entryReps
            }
            if let duration = entry.durationSeconds {
                durationSeconds += duration
            }
        }
        return weighted + Double(reps) + Double(durationSeconds) / 60.0
    }

    // MARK: - Recent PR

    /// The freshest all-time record (heaviest / distance / duration / reps) set within the
    /// recent window. Returns `nil` when the best of every metric predates the window.
    static func recentPR(entries: [SetEntry], now: Date, calendar: Calendar) -> RecentPR? {
        guard !entries.isEmpty else { return nil }
        guard let windowStart = calendar.date(byAdding: .day, value: -recentPRWindowDays, to: now) else { return nil }

        var candidates: [RecentPR] = []

        if let entry = recentRecordHolder(in: entries, value: { $0.weight }, windowStart: windowStart),
           let weight = entry.weight {
            candidates.append(RecentPR(
                metricTitle: "Heaviest",
                valueText: entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit),
                exerciseName: entry.exercise.name,
                date: entry.performedAt
            ))
        }

        if let entry = recentRecordHolder(in: entries, value: { $0.distance }, windowStart: windowStart),
           let distance = entry.distance {
            candidates.append(RecentPR(
                metricTitle: "Distance",
                valueText: entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit),
                exerciseName: entry.exercise.name,
                date: entry.performedAt
            ))
        }

        if let entry = recentRecordHolder(in: entries, value: { $0.durationSeconds.map(Double.init) }, windowStart: windowStart),
           let seconds = entry.durationSeconds {
            candidates.append(RecentPR(
                metricTitle: "Duration",
                valueText: DateHelper.formattedDuration(seconds: seconds),
                exerciseName: entry.exercise.name,
                date: entry.performedAt
            ))
        }

        if let entry = recentRecordHolder(in: entries, value: { $0.reps.map(Double.init) }, windowStart: windowStart),
           let reps = entry.reps {
            candidates.append(RecentPR(
                metricTitle: "Most Reps",
                valueText: reps == 1 ? "1 rep" : "\(reps) reps",
                exerciseName: entry.exercise.name,
                date: entry.performedAt
            ))
        }

        return candidates.max(by: { $0.date < $1.date })
    }

    /// Returns the most recent entry holding the all-time maximum of `value`, but only when
    /// that record falls on or after `windowStart`.
    private static func recentRecordHolder(
        in entries: [SetEntry],
        value: (SetEntry) -> Double?,
        windowStart: Date
    ) -> SetEntry? {
        let scored = entries.compactMap { entry -> (entry: SetEntry, value: Double)? in
            guard let value = value(entry), value > 0 else { return nil }
            return (entry, value)
        }
        guard let maxValue = scored.map(\.value).max() else { return nil }
        let holders = scored.filter { $0.value == maxValue }.map(\.entry)
        guard let mostRecent = holders.max(by: { $0.performedAt < $1.performedAt }) else { return nil }
        return mostRecent.performedAt >= windowStart ? mostRecent : nil
    }
}
