import SwiftUI
import XCTest
@testable import marble

final class StreakSnapshotTests: SnapshotTestCase {
    private func card(_ summary: StreakSummary) -> some View {
        StreakSummaryView(summary: summary)
            .padding(MarbleLayout.pagePadding)
    }

    func testStreakLoggedTodayAtBest() {
        // Live streak that also ties the all-time record: "Logged today" / "At your best".
        let summary = StreakSummary(current: 5, best: 5, loggedToday: true)
        assertSnapshot(card(summary), named: "Streak_LoggedToday_AtBest")
    }

    func testStreakAliveFromYesterday() {
        // Today not logged yet but the streak is still alive, below the all-time best.
        let summary = StreakSummary(current: 2, best: 9, loggedToday: false)
        assertSnapshot(card(summary), named: "Streak_AliveYesterday")
    }

    func testStreakBrokenWithHistory() {
        // Streak lapsed (no recent logging) but a personal best remains: a nudge to restart.
        let summary = StreakSummary(current: 0, best: 12, loggedToday: false)
        assertSnapshot(card(summary), named: "Streak_Broken")
    }
}
