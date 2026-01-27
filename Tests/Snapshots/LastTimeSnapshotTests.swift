import SwiftUI
import XCTest
@testable import marble

final class LastTimeSnapshotTests: SnapshotTestCase {
    func testLastTimeCardHistory() {
        let content = LastTimeContent(
            metrics: [
                LastTimeMetric(label: "Weight", value: "185 lb"),
                LastTimeMetric(label: "Reps", value: "5"),
                LastTimeMetric(label: "Rest", value: "1m 30s")
            ],
            loggedAtText: "Logged Jan 15, 2025 at 9:15 AM",
            emptyText: nil,
            accessibilityLabel: "Weight 185 lb, Reps 5, Rest 1m 30s, Logged Jan 15, 2025 at 9:15 AM",
            hasHistory: true
        )
        let view = LastTimeCardPreview(content: content)
        assertSnapshot(view, named: "LastTime_History")
    }

    func testLastTimeCardBodyweight() {
        let content = LastTimeContent(
            metrics: [
                LastTimeMetric(label: "Weight", value: "Bodyweight"),
                LastTimeMetric(label: "Reps", value: "12"),
                LastTimeMetric(label: "Rest", value: "1m")
            ],
            loggedAtText: "Logged Jan 15, 2025 at 9:15 AM",
            emptyText: nil,
            accessibilityLabel: "Weight Bodyweight, Reps 12, Rest 1m, Logged Jan 15, 2025 at 9:15 AM",
            hasHistory: true
        )
        let view = LastTimeCardPreview(content: content)
        assertSnapshot(view, named: "LastTime_Bodyweight")
    }

    func testLastTimeCardEmpty() {
        let content = LastTimeContent(
            metrics: [],
            loggedAtText: nil,
            emptyText: "No history for this exercise",
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
