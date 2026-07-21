import Foundation
import SwiftData
import WidgetKit

/// Writes the weekly-goal snapshot into the shared App Group suite and pokes
/// WidgetKit. App-only: the extension never touches SwiftData, it only reads
/// the published `WeeklyGoalWidgetState`.
///
/// Call it wherever `WeeklyGoalReminder.sync` is called — the two answer the
/// same question ("how does this week stand?") off the same store.
@MainActor
enum WeeklyGoalWidgetPublisher {
    /// Must match `WeeklyGoalWidget`'s `kind` in the extension.
    static let widgetKind = "WeeklyGoalWidget"

    /// `now` resolves inside the body rather than as a default argument:
    /// default arguments are evaluated in a nonisolated context, and
    /// `AppEnvironment.now` is main-actor isolated.
    static func publish(modelContext: ModelContext, now: Date? = nil) {
        guard !TestHooks.isUITesting else { return }

        let now = now ?? AppEnvironment.now
        let calendar = Calendar.current

        // Full history, deliberately unbounded — the same one-shot fetch
        // `TrendsView.fetchHistoryEntries()` feeds `TrainingConsistency`.
        //
        // NOTE: this does NOT mirror `WeeklyGoalReminder.sync`'s fetch. That
        // one is scoped to `performedAt >= weekStart` and its own comment says
        // so: "streak math isn't needed to decide whether THIS week still
        // needs sessions". `TrainingConsistency.snapshot` walks forward from
        // the earliest week present in `history`, so a current-week window
        // would pin `streakWeeks` and `flexTokens` to 0 — the two numbers the
        // medium/rectangular widget families exist to show. Matching Trends
        // instead also guarantees the widget and the Trends card never
        // disagree about the same week.
        let history = (try? modelContext.fetch(FetchDescriptor<SetEntry>())) ?? []

        let target = SharedDefaults.suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int
            ?? TrainingConsistency.defaultWeeklyTarget

        let snapshot = TrainingConsistency.snapshot(
            history: history,
            target: target,
            now: now,
            calendar: calendar
        )

        let state = WeeklyGoalWidgetState(
            target: snapshot.target,
            thisWeekSessions: snapshot.thisWeekSessions,
            streakWeeks: snapshot.streakWeeks,
            flexTokens: snapshot.flexTokens,
            stateRaw: raw(snapshot.state),
            weekStart: TrendsDateHelper.startOfWeek(for: now, calendar: calendar),
            generatedAt: now
        )

        state.save(to: SharedDefaults.suite)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// `GoalState` isn't `RawRepresentable`, and the extension can't see it
    /// anyway — this is the one place the mapping lives.
    static func raw(_ state: TrainingConsistency.GoalState) -> String {
        switch state {
        case .fresh: "fresh"
        case .hit: "hit"
        case .inProgress: "inProgress"
        case .atRisk: "atRisk"
        case .comeback: "comeback"
        }
    }
}
