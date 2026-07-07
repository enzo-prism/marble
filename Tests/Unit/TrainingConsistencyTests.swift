import XCTest
@testable import marble

/// Pins the weekly-goal engine: hit/missed weeks, flex-token earn/spend,
/// the comeback state, and at-risk detection. The fixed test clock is
/// Wednesday 2025-01-15 in GMT; weeks run Sunday–Saturday, so the current
/// week starts Sunday 2025-01-12 with four days left including today.
final class TrainingConsistencyTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private var currentWeekStart: Date {
        TrendsDateHelper.startOfWeek(for: now, calendar: calendar)
    }

    /// A set on `weeksAgo` weeks before the current week, `dayOffset` days
    /// into that week.
    private func session(_ exercise: Exercise, weeksAgo: Int, dayOffset: Int, hour: Int = 9) -> SetEntry {
        let weekStart = calendar.date(byAdding: .day, value: -weeksAgo * 7, to: currentWeekStart) ?? currentWeekStart
        let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        let performedAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return SetEntry(exercise: exercise, performedAt: performedAt, weight: 100, weightUnit: .lb, reps: 5, restAfterSeconds: 90)
    }

    func testEmptyHistoryIsFresh() {
        let snapshot = TrainingConsistency.snapshot(history: [], target: 3, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.streakWeeks, 0)
        XCTAssertEqual(snapshot.lifetimeSets, 0)
    }

    func testHittingTargetThisWeekBanksTheWeek() {
        let exercise = bench()
        let history = [
            session(exercise, weeksAgo: 0, dayOffset: 0),
            session(exercise, weeksAgo: 0, dayOffset: 1),
            session(exercise, weeksAgo: 0, dayOffset: 2)
        ]

        let snapshot = TrainingConsistency.snapshot(history: history, target: 3, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.state, .hit)
        XCTAssertEqual(snapshot.thisWeekSessions, 3)
        XCTAssertEqual(snapshot.streakWeeks, 1)
    }

    func testFourConsecutiveHitWeeksEarnAFlexToken() {
        let exercise = bench()
        var history: [SetEntry] = []
        for weeksAgo in 1...8 {
            history.append(session(exercise, weeksAgo: weeksAgo, dayOffset: 1))
            history.append(session(exercise, weeksAgo: weeksAgo, dayOffset: 3))
        }

        let snapshot = TrainingConsistency.snapshot(history: history, target: 2, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.streakWeeks, 8)
        XCTAssertEqual(snapshot.flexTokens, 2, "Tokens earn at weeks 4 and 8, capped at 2")
        XCTAssertEqual(snapshot.state, .inProgress)
    }

    func testFlexTokenAbsorbsAMissedWeek() {
        let exercise = bench()
        var history: [SetEntry] = []
        // Weeks 5..2 ago: four hit weeks earn one token. Last week: nothing.
        for weeksAgo in 2...5 {
            history.append(session(exercise, weeksAgo: weeksAgo, dayOffset: 1))
            history.append(session(exercise, weeksAgo: weeksAgo, dayOffset: 3))
        }
        history.append(session(exercise, weeksAgo: 0, dayOffset: 1))

        let snapshot = TrainingConsistency.snapshot(history: history, target: 2, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.streakWeeks, 5, "4 hits + 1 flexed week")
        XCTAssertEqual(snapshot.flexTokens, 0, "The token was spent on the missed week")
        XCTAssertEqual(snapshot.state, .inProgress)
    }

    func testMissWithoutTokenResetsAndComebackIsCelebrated() {
        let exercise = bench()
        var history: [SetEntry] = []
        // One hit week (no token yet), then a missed week, then a session now.
        history.append(session(exercise, weeksAgo: 2, dayOffset: 1))
        history.append(session(exercise, weeksAgo: 2, dayOffset: 3))
        history.append(session(exercise, weeksAgo: 0, dayOffset: 1))

        let snapshot = TrainingConsistency.snapshot(history: history, target: 2, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.streakWeeks, 0)
        XCTAssertEqual(snapshot.state, .comeback)
        XCTAssertEqual(snapshot.lifetimeActiveDays, 3, "Lifetime totals survive the broken streak")
    }

    func testAtRiskWhenEveryRemainingDayIsNeeded() {
        let exercise = bench()
        // Today (Wednesday) is already trained; 4 more sessions needed with
        // only Thu/Fri/Sat left.
        let history = [session(exercise, weeksAgo: 0, dayOffset: 3)]

        let snapshot = TrainingConsistency.snapshot(history: history, target: 5, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.state, .atRisk)
    }

    func testTargetClampsToSaneRange() {
        let exercise = bench()
        let history = [session(exercise, weeksAgo: 0, dayOffset: 1)]

        XCTAssertEqual(TrainingConsistency.snapshot(history: history, target: 0, now: now, calendar: calendar).target, 1)
        XCTAssertEqual(TrainingConsistency.snapshot(history: history, target: 99, now: now, calendar: calendar).target, 7)
    }

    func testReminderPlanFiresOnLastWinnableEvening() {
        let snapshot = TrainingConsistency.Snapshot(
            target: 3,
            thisWeekSessions: 1,
            streakWeeks: 4,
            flexTokens: 1,
            state: .inProgress,
            lifetimeActiveDays: 30,
            lifetimeSets: 300
        )

        let plan = WeeklyGoalReminder.plan(snapshot: snapshot, now: now, calendar: calendar)

        XCTAssertNotNil(plan)
        // 2 sessions needed → last winnable start day is weekStart + 5 (Friday).
        let expectedDay = calendar.date(byAdding: .day, value: 5, to: currentWeekStart)!
        XCTAssertEqual(calendar.startOfDay(for: plan!.fireDate), calendar.startOfDay(for: expectedDay))
        XCTAssertEqual(calendar.component(.hour, from: plan!.fireDate), WeeklyGoalReminder.fireHour)
        XCTAssertTrue(plan!.body.contains("4-week streak"), "The streak is the stake: \(plan!.body)")
    }

    func testReminderPlanSilentOnceTargetHit() {
        let snapshot = TrainingConsistency.Snapshot(
            target: 3,
            thisWeekSessions: 3,
            streakWeeks: 4,
            flexTokens: 1,
            state: .hit,
            lifetimeActiveDays: 30,
            lifetimeSets: 300
        )

        XCTAssertNil(WeeklyGoalReminder.plan(snapshot: snapshot, now: now, calendar: calendar))
    }
}
