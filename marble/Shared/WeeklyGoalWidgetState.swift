import Foundation

/// The weekly-goal snapshot the app hands to the widget extension through the
/// shared App Group suite.
///
/// Compiled into BOTH targets, so Foundation only. `stateRaw` is a String
/// rather than `TrainingConsistency.GoalState` precisely because the widget
/// extension cannot see the app's engine — the app maps the enum on the way
/// in, the widget switches on the string on the way out.
nonisolated struct WeeklyGoalWidgetState: Codable, Hashable, Sendable {
    /// Anything older than a full week plus a day describes a week that has
    /// already rolled over, so it is no longer safe to render as "this week".
    static let stalenessInterval: TimeInterval = 8 * 24 * 60 * 60

    var target: Int
    var thisWeekSessions: Int
    var streakWeeks: Int
    var flexTokens: Int
    /// Mirrors `TrainingConsistency.GoalState`:
    /// "fresh" | "hit" | "inProgress" | "atRisk" | "comeback".
    var stateRaw: String
    var weekStart: Date
    var generatedAt: Date

    /// Representative data for the widget gallery only — never persisted.
    /// Its dates are resolved at first access (not epoch) so the gallery
    /// preview isn't immediately classified stale and downgraded to the
    /// neutral "Open Marble" card.
    static let placeholder = WeeklyGoalWidgetState(
        target: 3,
        thisWeekSessions: 2,
        streakWeeks: 3,
        flexTokens: 1,
        stateRaw: "inProgress",
        weekStart: Date(),
        generatedAt: Date()
    )

    /// True once the snapshot is older than `stalenessInterval`. Exactly at
    /// the boundary still counts as fresh.
    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > Self.stalenessInterval
    }

    /// Progress through this week's target, clamped to 0...1. A non-positive
    /// target has no meaningful progress, so it reads 0.
    var progressFraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(thisWeekSessions) / Double(target)))
    }

    static func load(from defaults: UserDefaults) -> WeeklyGoalWidgetState? {
        guard let data = defaults.data(forKey: SharedDefaults.Key.weeklyGoalSnapshot) else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalWidgetState.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: SharedDefaults.Key.weeklyGoalSnapshot)
    }
}
