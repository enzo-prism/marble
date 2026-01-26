import SwiftUI
import XCTest
@testable import marble

final class LastTimeSnapshotTests: SnapshotTestCase {
    func testLastTimeCardHistory() {
        let content = LastTimeContent(
            primaryText: "185 lb · 5 reps · Rest 1m 30s",
            secondaryText: "Logged Jan 15, 2025 at 9:15 AM",
            accessibilityLabel: "185 lb, 5 reps, Rest 1m 30s, Logged Jan 15, 2025 at 9:15 AM",
            hasHistory: true
        )
        let view = LastTimeCardPreview(content: content)
        assertSnapshot(view, named: "LastTime_History")
    }

    func testLastTimeCardBodyweight() {
        let content = LastTimeContent(
            primaryText: "Bodyweight · 12 reps · Rest 1m",
            secondaryText: "Logged Jan 15, 2025 at 9:15 AM",
            accessibilityLabel: "Bodyweight, 12 reps, Rest 1m, Logged Jan 15, 2025 at 9:15 AM",
            hasHistory: true
        )
        let view = LastTimeCardPreview(content: content)
        assertSnapshot(view, named: "LastTime_Bodyweight")
    }

    func testLastTimeCardEmpty() {
        let content = LastTimeContent(
            primaryText: "No history for this exercise",
            secondaryText: nil,
            accessibilityLabel: "No history for this exercise",
            hasHistory: false
        )
        let view = LastTimeCardPreview(content: content)
        assertSnapshot(view, named: "LastTime_Empty")
    }
}

private struct LastTimeCardPreview: View {
    let content: LastTimeContent

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            SectionHeaderView(title: "Last time")
            LastTimeCardView(content: content)
        }
        .padding(MarbleLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
