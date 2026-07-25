import SwiftUI
import WidgetKit

// NOTE: This file belongs to the **MarbleWidgets widget-extension target**.
// `SharedDefaults.swift` (which also defines `SharedKeychain`, the transport
// this file reads), `WeeklyGoalWidgetState.swift`, and
// `WeeklyGoalWidgetViews.swift` — all three under `marble/Shared/` — must be
// added to this target's membership too; see
// SETUP.md and the RestTimerAttributes.swift precedent. The extension needs
// the `keychain-access-groups` entitlement in MarbleWidgets.entitlements to
// read the snapshot at all.
//
// The five family layouts live in `marble/Shared/WeeklyGoalWidgetViews.swift`
// so the app's snapshot suite can render them; everything that cannot leave the
// extension — the `Widget`, the `TimelineProvider`, the keychain read — stays
// here.
//
// Brand rules that apply here: monochrome, no Liquid Glass on content, no
// emoji, leaf-level accessibility identifiers only.

// MARK: - Timeline

nonisolated struct WeeklyGoalEntry: TimelineEntry {
    let date: Date
    /// nil means "nothing trustworthy to show" — render the neutral card
    /// rather than inventing numbers.
    let state: WeeklyGoalWidgetState?

    /// Smart Stack ranking for this entry, scored at the entry's own date so
    /// the week-boundary entries (which re-validate `state` per date) also
    /// re-score. The scoring itself is pure and lives with the snapshot
    /// (`WeeklyGoalWidgetState.relevanceScore`) so the app target's unit
    /// suite can pin it — this file never joins the test target.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: WeeklyGoalWidgetState.relevanceScore(for: state, at: date))
    }
}

/// `nonisolated` on purpose: the target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and `TimelineProvider`'s
/// requirements are not main-actor isolated.
nonisolated struct WeeklyGoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalEntry {
        WeeklyGoalEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalEntry) -> Void) {
        let now = Date()
        // The gallery always gets representative data; a real install gets
        // the truth, including the neutral card when there is none.
        let state = context.isPreview ? WeeklyGoalWidgetState.placeholder : currentState(now: now)
        completion(WeeklyGoalEntry(date: now, state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let loaded = WeeklyGoalWidgetState.loadPublished()

        let nextDay = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60 * 24)

        // The next week boundary is a property of `now`, never of the snapshot:
        // deriving it from a published `weekStart` that had already rolled over
        // put the boundary in the past and lost the rollover entry entirely.
        let weekStart = WeeklyGoalWidgetState.startOfWeek(for: now, calendar: calendar)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? nextDay

        // **Each entry is re-validated against its own date.** Reusing one
        // state across the boundary entries is what made the week rollover
        // actively re-render last week's numbers instead of clearing them.
        var entries = [WeeklyGoalEntry(date: now, state: state(loaded, at: now, calendar: calendar))]
        // Sorted + deduplicated: on a Saturday `nextDay` and `nextWeek` are the
        // same instant, and WidgetKit wants strictly ordered entries.
        for boundary in Set([nextDay, nextWeek]).filter({ $0 > now }).sorted() {
            entries.append(WeeklyGoalEntry(date: boundary, state: state(loaded, at: boundary, calendar: calendar)))
        }

        let refreshAt = min(nextDay, nextWeek > now ? nextWeek : nextDay)
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }

    /// Nil covers every "nothing trustworthy to show" case identically:
    /// nothing published yet, a snapshot describing a week that has already
    /// rolled over, one older than the staleness limit, or an unreadable
    /// keychain (no entitlement on the simulator, first-unlock not yet
    /// reached). All of them render the neutral "Open Marble" card.
    private func currentState(now: Date) -> WeeklyGoalWidgetState? {
        state(WeeklyGoalWidgetState.loadPublished(), at: now, calendar: .current)
    }

    /// The snapshot as it should be rendered *at `date`*, or nil.
    private func state(
        _ loaded: WeeklyGoalWidgetState?,
        at date: Date,
        calendar: Calendar
    ) -> WeeklyGoalWidgetState? {
        guard let loaded, loaded.isRenderable(now: date, calendar: calendar) else { return nil }
        return loaded
    }
}

// MARK: - Widget

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyGoalWidget", provider: WeeklyGoalProvider()) { entry in
            WeeklyGoalWidgetContent(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Goal")
        .description("Sessions logged against this week's training target.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
