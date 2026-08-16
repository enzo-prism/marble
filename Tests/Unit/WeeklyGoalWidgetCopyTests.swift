import XCTest
@testable import marble

/// Pins the widget's copy layer — the strings every Weekly Goal family renders.
/// Cheap to run and it covers the two things a snapshot cannot assert: that each
/// `stateRaw` maps to its intended sentence, and that an unknown state falls back
/// to the neutral line rather than showing nothing.
@MainActor
final class WeeklyGoalWidgetCopyTests: XCTestCase {
    private func state(
        target: Int = 3,
        sessions: Int = 2,
        streak: Int = 4,
        flex: Int = 1,
        stateRaw: String = "inProgress"
    ) -> WeeklyGoalWidgetState {
        WeeklyGoalWidgetState(
            target: target,
            thisWeekSessions: sessions,
            streakWeeks: streak,
            flexTokens: flex,
            stateRaw: stateRaw,
            weekStart: Date(timeIntervalSince1970: 1_750_000_000),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    func testProgressAndSessionsCopy() {
        XCTAssertEqual(WeeklyGoalCopy.progress(state()), "2 of 3")
        XCTAssertEqual(WeeklyGoalCopy.sessions(state()), "2 of 3 sessions")
    }

    func testStreakAndFlexUseSingularForOne() {
        XCTAssertEqual(WeeklyGoalCopy.streak(state(streak: 1)), "1-week streak")
        XCTAssertEqual(WeeklyGoalCopy.streak(state(streak: 5)), "5-week streak")
        XCTAssertEqual(WeeklyGoalCopy.flex(state(flex: 1)), "1 flex week banked")
        XCTAssertEqual(WeeklyGoalCopy.flex(state(flex: 2)), "2 flex weeks banked")
    }

    func testLockScreenCopyDropsTwoDigitStreaks() {
        XCTAssertEqual(
            WeeklyGoalCopy.compactLockScreenProgress(state(sessions: 1, streak: 6)),
            "1 of 3 · 6-week streak"
        )
        XCTAssertEqual(
            WeeklyGoalCopy.compactLockScreenProgress(state(sessions: 1, streak: 12)),
            "1 of 3"
        )
    }

    func testEveryGoalStateHasItsOwnLine() {
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "fresh")), "Log a set to start the week.")
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "hit")), "Target hit. Week banked.")
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "atRisk")), "Every remaining day counts.")
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "comeback")), "Back on track.")
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "inProgress")), "On track for this week.")
    }

    /// `stateRaw` crosses a process boundary as a plain string, so an unknown
    /// value has to degrade to the neutral line rather than render empty.
    func testUnknownStateFallsBackToTheNeutralLine() {
        XCTAssertEqual(WeeklyGoalCopy.stateLine(state(stateRaw: "somethingNew")), "On track for this week.")
    }

    func testAccessibilityStringCombinesSessionsStreakAndState() {
        XCTAssertEqual(
            WeeklyGoalCopy.accessibility(state()),
            "2 of 3 sessions this week. 4-week streak. On track for this week."
        )
    }
}
