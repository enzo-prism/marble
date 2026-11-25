import XCTest
@testable import marble

final class TrendsDeltaTextTests: XCTestCase {
    func testSmallChangesReadAsPercentages() {
        XCTAssertEqual(TrendsDeltaPill.text(for: 0.2), "Even")
        XCTAssertEqual(TrendsDeltaPill.text(for: 14.4), "14%")
        XCTAssertEqual(TrendsDeltaPill.text(for: -32), "32%")
        XCTAssertEqual(TrendsDeltaPill.text(for: 199), "199%")
    }

    func testLargeGainsReadAsMultiples() {
        XCTAssertEqual(TrendsDeltaPill.text(for: 200), "3×")
        XCTAssertEqual(TrendsDeltaPill.text(for: 240), "3.4×")
        XCTAssertEqual(TrendsDeltaPill.text(for: 899), "10×")
        // A token comparison week is bounded, never "2222×".
        XCTAssertEqual(TrendsDeltaPill.text(for: 222_100), "10×+")
    }

    func testAccessibilityTextMatchesTheVisibleForm() {
        XCTAssertEqual(
            TrendsDeltaPill.accessibilityText(for: 14.4, comparisonLabel: "week before"),
            "Up 14 percent from the week before"
        )
        XCTAssertEqual(
            TrendsDeltaPill.accessibilityText(for: 240, comparisonLabel: "week before"),
            "3.4 times the week before"
        )
        XCTAssertEqual(
            TrendsDeltaPill.accessibilityText(for: 5_000, comparisonLabel: "week before"),
            "More than 10 times the week before"
        )
    }

    func testTrainedMusclesNeverReadZeroPerWeek() {
        XCTAssertEqual(MuscleGroupSectionView.perWeekText(0), "0.0")
        XCTAssertEqual(MuscleGroupSectionView.perWeekText(0.02), "<0.1")
        XCTAssertEqual(MuscleGroupSectionView.perWeekText(0.06), "0.1")
        XCTAssertEqual(MuscleGroupSectionView.perWeekText(12.34), "12.3")
    }
}
