import Foundation

/// Current and all-time-best **daily** training streaks.
///
/// A day counts toward a streak when it has at least one logged ``SetEntry``. Logging
/// nothing on a completed day breaks the streak. Today is treated as still in progress:
/// an as-yet-unlogged today never *breaks* a streak that was alive yesterday — the user
/// has until midnight to keep it — but it also doesn't extend the count until a set lands.
struct StreakSummary: Equatable {
    /// Consecutive logged days ending today (or yesterday, while today is still open).
    let current: Int
    /// Longest run of consecutive logged days across the entire history.
    let best: Int
    /// Whether today already has at least one logged set.
    let loggedToday: Bool

    /// True once there is any logged history to describe a streak against.
    var hasHistory: Bool { best > 0 }

    static let empty = StreakSummary(current: 0, best: 0, loggedToday: false)
}

enum StreakBuilder {
    /// A streak only reads as meaningful in the Trends momentum strip once it spans at
    /// least this many days; a lone day isn't yet a "streak".
    static let minimumStreakDays = 2

    /// Builds the full streak summary (current + best) from a set of logged entries.
    /// - Parameter entries: any collection of set entries (order does not matter). Pass
    ///   exercise-scoped entries to measure a streak for a single exercise.
    static func build(
        entries: [SetEntry],
        now: Date = AppEnvironment.now,
        calendar: Calendar = .current
    ) -> StreakSummary {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.performedAt) })
        guard !activeDays.isEmpty else { return .empty }

        let today = calendar.startOfDay(for: now)
        return StreakSummary(
            current: currentStreak(activeDays: activeDays, today: today, calendar: calendar),
            best: longestStreak(activeDays: activeDays, calendar: calendar),
            loggedToday: activeDays.contains(today)
        )
    }

    /// Convenience for callers that only need the live count (e.g. the Trends momentum chip).
    static func currentStreak(
        entries: [SetEntry],
        now: Date = AppEnvironment.now,
        calendar: Calendar = .current
    ) -> Int {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.performedAt) })
        guard !activeDays.isEmpty else { return 0 }
        return currentStreak(activeDays: activeDays, today: calendar.startOfDay(for: now), calendar: calendar)
    }

    // MARK: - Internals

    private static func currentStreak(activeDays: Set<Date>, today: Date, calendar: Calendar) -> Int {
        // Anchor the walk at today when it's already logged, otherwise at yesterday so an
        // in-progress day never counts as a miss. If neither is active the streak is broken.
        let cursorStart: Date
        if activeDays.contains(today) {
            cursorStart = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  activeDays.contains(yesterday) {
            cursorStart = yesterday
        } else {
            return 0
        }

        var cursor = cursorStart
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func longestStreak(activeDays: Set<Date>, calendar: Calendar) -> Int {
        let sortedDays = activeDays.sorted()
        var longest = 0
        var run = 0
        var previousDay: Date?
        for day in sortedDays {
            if let previousDay,
               let nextExpected = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(day, inSameDayAs: nextExpected) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previousDay = day
        }
        return longest
    }
}
