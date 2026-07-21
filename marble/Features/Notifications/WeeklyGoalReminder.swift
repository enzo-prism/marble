import Foundation
import SwiftData
import UserNotifications

/// The one adaptive nudge in the app: a single, quiet, non-repeating
/// notification on the last realistic evening to keep the weekly goal alive.
///
/// Anti-spam rules, all deliberate:
/// - At most ONE pending nudge, replaced wholesale on every sync.
/// - Cancelled the moment the week's target is hit — never notifies about
///   something already done.
/// - `.passive` interruption level: no sound, no Focus break, sits in
///   Notification Center ("streak at risk" is real but it is not urgent).
/// - Never prompts for permission — it rides on the authorization the user
///   already granted for their own reminders, and stays silent otherwise.
enum WeeklyGoalReminder {
    static let requestIdentifier = "marble.weeklyGoal.atRisk"
    /// Same literal key as before — it now lives in the shared App Group
    /// suite (see `SharedDefaults`) so the widget extension can read it.
    static let enabledDefaultsKey = SharedDefaults.Key.weeklyGoalReminderEnabled
    /// Evening hour the nudge fires at.
    static let fireHour = 18

    struct Plan: Equatable {
        let fireDate: Date
        let body: String
    }

    /// Pure planning: when (if ever) the nudge should fire for this snapshot.
    /// Fires on the first evening where the remaining days exactly equal the
    /// remaining sessions — the last point the week is still fully winnable.
    static func plan(
        snapshot: TrainingConsistency.Snapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Plan? {
        guard snapshot.state != .fresh, snapshot.state != .hit else { return nil }
        let needed = snapshot.target - snapshot.thisWeekSessions
        guard needed > 0 else { return nil }

        let weekStart = TrendsDateHelper.startOfWeek(for: now, calendar: calendar)
        // Last day the goal is still winnable training every remaining day.
        guard let lastStartDay = calendar.date(byAdding: .day, value: 7 - needed, to: weekStart) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: lastStartDay)
        components.hour = fireHour
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        let sessionText = needed == 1 ? "One session" : "\(needed) sessions"
        let body: String
        if snapshot.streakWeeks > 0 {
            let streakText = snapshot.streakWeeks == 1 ? "1-week streak" : "\(snapshot.streakWeeks)-week streak"
            body = "\(sessionText) keeps your \(streakText) alive — still doable this week."
        } else {
            body = "\(sessionText) still gets you to \(snapshot.target) this week."
        }
        return Plan(fireDate: fireDate, body: body)
    }

    /// Recomputes and replaces the pending nudge. Call on app foreground and
    /// background — cheap (one indexed fetch) and idempotent.
    @MainActor
    static func sync(modelContext: ModelContext, now suppliedNow: Date? = nil) async {
        let now = suppliedNow ?? AppEnvironment.now
        guard !TestHooks.isUITesting else { return }
        guard SharedDefaults.suite.object(forKey: enabledDefaultsKey) as? Bool ?? true else {
            removePending()
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let target = SharedDefaults.suite.object(forKey: SharedDefaults.Key.weeklySessionTarget) as? Int
            ?? TrainingConsistency.defaultWeeklyTarget
        // The engine only needs day-level activity; scoping the fetch to the
        // current week keeps this sync O(week) — streak math isn't needed to
        // decide whether THIS week still needs sessions.
        let calendar = Calendar.current
        let weekStart = TrendsDateHelper.startOfWeek(for: now, calendar: calendar)
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.performedAt >= weekStart }
        )
        let weekEntries = (try? modelContext.fetch(descriptor)) ?? []
        let sessions = Set(weekEntries.map { calendar.startOfDay(for: $0.performedAt) }).count

        removePending()
        guard sessions < target else { return }

        let snapshot = TrainingConsistency.Snapshot(
            target: max(1, min(target, 7)),
            thisWeekSessions: sessions,
            streakWeeks: 0,
            flexTokens: 0,
            state: .inProgress,
            lifetimeActiveDays: 0,
            lifetimeSets: 1
        )
        guard let plan = plan(snapshot: snapshot, now: now, calendar: calendar) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weekly goal"
        content.body = plan.body
        content.interruptionLevel = .passive

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func removePending() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }
}
