import Foundation

/// Pure engine behind the weekly training goal: a weekly session target,
/// a week streak that forgives with banked flex weeks, and a state machine
/// tuned to bring lifters back rather than shame them.
///
/// Design anchors:
/// - The unit is the WEEK, not the day — training has rest days by design
///   (the daily-ring model penalizes exactly the recovery good programs need).
/// - Missing once doesn't undo a habit; missing twice in a row starts to
///   (Lally 2010). Flex weeks encode "never miss twice" as a bankable reserve.
/// - The comeback is celebrated: rewarding the return after a lapse
///   outperformed every other intervention in the Milkman 2021 megastudy.
enum TrainingConsistency {
    /// Sessions (active days) per week that count as a hit week.
    static let defaultWeeklyTarget = 3
    /// Consecutive hit weeks that earn one flex week.
    static let hitWeeksPerFlexToken = 4
    /// Most flex weeks that can sit in the bank.
    static let maxFlexTokens = 2

    enum WeekOutcome: Equatable {
        case hit
        /// Missed, but a banked flex week absorbed it — streak preserved.
        case flexed
        case missed
    }

    enum GoalState: Equatable {
        /// No sets ever logged.
        case fresh
        /// This week's target already hit.
        case hit
        /// Week under way, target still comfortably reachable.
        case inProgress
        /// Hitting the target now needs a session on every remaining day.
        case atRisk
        /// First sessions after a broken streak — "back on track".
        case comeback
    }

    struct Snapshot: Equatable {
        let target: Int
        let thisWeekSessions: Int
        /// Consecutive hit-or-flexed weeks, including this week once it's hit.
        let streakWeeks: Int
        let flexTokens: Int
        let state: GoalState
        /// All-time training days — the identity number a broken streak
        /// can never zero.
        let lifetimeActiveDays: Int
        let lifetimeSets: Int

        static let empty = Snapshot(
            target: defaultWeeklyTarget,
            thisWeekSessions: 0,
            streakWeeks: 0,
            flexTokens: 0,
            state: .fresh,
            lifetimeActiveDays: 0,
            lifetimeSets: 0
        )
    }

    static func snapshot(
        history: [SetEntry],
        target rawTarget: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Snapshot {
        let target = max(1, min(rawTarget, 7))
        guard !history.isEmpty else {
            return Snapshot(
                target: target,
                thisWeekSessions: 0,
                streakWeeks: 0,
                flexTokens: 0,
                state: .fresh,
                lifetimeActiveDays: 0,
                lifetimeSets: 0
            )
        }

        let activeDays = Set(history.map { calendar.startOfDay(for: $0.performedAt) })
        let currentWeekStart = TrendsDateHelper.startOfWeek(for: now, calendar: calendar)

        var sessionsPerWeek: [Date: Int] = [:]
        for day in activeDays {
            let weekStart = TrendsDateHelper.startOfWeek(for: day, calendar: calendar)
            sessionsPerWeek[weekStart, default: 0] += 1
        }
        let thisWeekSessions = sessionsPerWeek[currentWeekStart] ?? 0

        // Walk every completed week from the first active one, earning and
        // spending flex tokens in order.
        var streak = 0
        var tokens = 0
        var consecutiveHits = 0
        var lastCompletedOutcome: WeekOutcome?

        if let firstWeek = sessionsPerWeek.keys.min(), firstWeek < currentWeekStart {
            var week = firstWeek
            while week < currentWeekStart {
                let sessions = sessionsPerWeek[week] ?? 0
                if sessions >= target {
                    streak += 1
                    consecutiveHits += 1
                    if consecutiveHits.isMultiple(of: hitWeeksPerFlexToken) {
                        tokens = min(tokens + 1, maxFlexTokens)
                    }
                    lastCompletedOutcome = .hit
                } else if tokens > 0 {
                    tokens -= 1
                    streak += 1
                    consecutiveHits = 0
                    lastCompletedOutcome = .flexed
                } else {
                    streak = 0
                    consecutiveHits = 0
                    lastCompletedOutcome = .missed
                }
                guard let next = calendar.date(byAdding: .day, value: 7, to: week) else { break }
                week = next
            }
        }

        let state: GoalState
        if thisWeekSessions >= target {
            streak += 1
            state = .hit
        } else if lastCompletedOutcome == .missed, thisWeekSessions > 0 {
            state = .comeback
        } else {
            let today = calendar.startOfDay(for: now)
            let daysElapsed = calendar.dateComponents([.day], from: currentWeekStart, to: today).day ?? 0
            let daysLeft = max(0, 7 - daysElapsed)
            let needed = target - thisWeekSessions
            // Today only counts as usable if it isn't already a training day.
            let usableDays = max(0, activeDays.contains(today) ? daysLeft - 1 : daysLeft)
            // At risk = every remaining day must be a session (or the week is
            // already short). Anything looser is just a week in progress.
            state = needed >= usableDays ? .atRisk : .inProgress
        }

        return Snapshot(
            target: target,
            thisWeekSessions: thisWeekSessions,
            streakWeeks: streak,
            flexTokens: tokens,
            state: state,
            lifetimeActiveDays: activeDays.count,
            lifetimeSets: history.count
        )
    }
}
