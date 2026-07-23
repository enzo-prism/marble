import Foundation

/// The weekly-goal snapshot the app hands to the widget extension through
/// `SharedKeychain` — a generic-password item in the team-prefixed keychain
/// access group both targets are entitled to. (It travelled through an App
/// Group suite in 2.2; see `SharedDefaults` for why that group is gone.)
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
    ///
    /// Age alone is **not** enough to decide the snapshot is renderable — see
    /// `describesWeek(containing:)`. A snapshot published Saturday 23:00 is one
    /// hour old at Sunday 00:00 and yet already describes last week.
    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > Self.stalenessInterval
    }

    // MARK: - Week identity

    /// The canonical week anchor for both targets.
    ///
    /// Must stay identical to the app's `TrendsDateHelper.startOfWeek(for:)` —
    /// same `dateInterval(of: .weekOfYear:)` rule, same `startOfDay` fallback —
    /// because the app writes `weekStart` with that helper and the widget
    /// compares against this one. The extension cannot see `TrendsDateHelper`,
    /// so the rule is duplicated here rather than shared.
    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// True when this snapshot still describes the week `now` falls in.
    ///
    /// Both sides are normalised through `startOfWeek` rather than comparing
    /// the stored `weekStart` raw, so a lifter who crosses a time zone gets the
    /// same week rather than a blanked widget.
    func describesWeek(containing now: Date, calendar: Calendar = .current) -> Bool {
        Self.startOfWeek(for: weekStart, calendar: calendar)
            == Self.startOfWeek(for: now, calendar: calendar)
    }

    /// The single gate the widget renders behind: the snapshot must describe
    /// the current week *and* not be stale.
    ///
    /// Week identity is the real check — the 8-day age limit is only a second
    /// line of defence for a snapshot whose `weekStart` is somehow unusable.
    /// Rendering last week's "4 of 3 · Target hit" on Sunday morning of a week
    /// with zero sessions is the bug this exists to prevent.
    func isRenderable(now: Date, calendar: Calendar = .current) -> Bool {
        describesWeek(containing: now, calendar: calendar) && !isStale(now: now)
    }

    /// Progress through this week's target, clamped to 0...1. A non-positive
    /// target has no meaningful progress, so it reads 0.
    var progressFraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(thisWeekSessions) / Double(target)))
    }

    // MARK: - Smart Stack relevance (pure — no WidgetKit)

    /// Population-typical gym windows, in local-calendar hours. The snapshot
    /// carries no per-user schedule, so these are deliberately broad; the
    /// *personalised* half of Smart Stack timing comes from `LogSetIntent`'s
    /// `PredictableIntent` donations, not from here.
    static let morningTrainingHours = 6...9
    static let eveningTrainingHours = 16...20

    /// How strongly the Smart Stack should surface the widget at `date`,
    /// 0...1. Foundation-only and pure so the app target's unit suite can pin
    /// it — the widget extension (which the test target cannot see) merely
    /// wraps the result in a `TimelineEntryRelevance`.
    ///
    /// The shape, per Apple's guidance that scores rank a widget against its
    /// *own* other moments, not against other apps:
    /// - nil or unrenderable snapshot → 0: never rotate in the neutral card.
    /// - week already hit → 0.1: a banked week is a glance, not a nudge.
    /// - one session remaining → 0.7, the strongest standing claim.
    /// - progress made mid-week → 0.4; nothing logged yet → 0.25.
    /// - +0.3 (capped at 1) inside a typical training window, so the peak
    ///   scores land when acting on the widget is actually plausible.
    static func relevanceScore(
        for state: WeeklyGoalWidgetState?,
        at date: Date,
        calendar: Calendar = .current
    ) -> Float {
        guard let state,
              state.isRenderable(now: date, calendar: calendar),
              state.target > 0 else { return 0 }

        let remaining = state.target - state.thisWeekSessions
        guard remaining > 0 else { return 0.1 }

        let base: Float = remaining == 1 ? 0.7 : (state.thisWeekSessions > 0 ? 0.4 : 0.25)
        let hour = calendar.component(.hour, from: date)
        let inWindow = Self.morningTrainingHours.contains(hour)
            || Self.eveningTrainingHours.contains(hour)
        return min(1, base + (inWindow ? 0.3 : 0))
    }

    // MARK: - Wire format (pure — no keychain, no defaults)

    /// The bytes that go on the wire, or nil if this value somehow can't be
    /// encoded. Split out from `publish()` so tests can pin the wire format
    /// without a keychain in the loop.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        // Sorted keys make equal states encode to identical bytes. Without it
        // JSON key order varies between encodes, so an unchanged week would
        // still rewrite the keychain item on every scene transition.
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(self)
    }

    /// The inverse of `encoded()`. Tolerates nil (nothing published) and
    /// garbage (a truncated or foreign payload) identically: no snapshot,
    /// which the widget renders as the neutral "Open Marble" card.
    static func decoded(from data: Data?) -> WeeklyGoalWidgetState? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalWidgetState.self, from: data)
    }

    // MARK: - Transport (thin wrapper over SharedKeychain)

    /// Reads whatever the app last published. Nil when nothing has been
    /// published yet *or* the keychain is unreadable — the widget treats both
    /// the same way on purpose.
    static func loadPublished() -> WeeklyGoalWidgetState? {
        decoded(from: SharedKeychain.loadSnapshot())
    }

    /// Publishes this snapshot for the widget extension. Silently does nothing
    /// if encoding or the keychain write fails; the widget then keeps showing
    /// the previous snapshot until it goes stale.
    func publish() {
        guard let data = encoded() else { return }
        SharedKeychain.saveSnapshot(data)
    }
}
