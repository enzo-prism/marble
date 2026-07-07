import XCTest

final class TrendsSelectionUITests: MarbleUITestCase {
    func testTrendsConsistencySelectionOpensDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let chart = chartElement("Trends.ConsistencyChart")
        waitFor(chart)

        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let list = waitForIdentifier("Trends.DaySheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    func testTrendsWeeklyVolumeSelectionOpensWeekDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let scrollView = app.scrollViews["Trends.Scroll"]
        let volumeChart = chartElement("Trends.VolumeChart")
        // The coaching sections above the chart make the page taller than a
        // few blind swipes; scroll until the chart is actually on screen so
        // the normalized-coordinate tap lands inside the plot.
        scrollToElement(volumeChart, in: scrollView)
        waitFor(volumeChart)

        volumeChart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)).tap()

        let list = waitForIdentifier("Trends.WeekSheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    func testTrendsSupplementsSelectionOpensSupplementDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let scrollView = app.scrollViews["Trends.Scroll"]
        let supplementsChart = chartElement("Trends.SupplementsChart")
        scrollToElement(supplementsChart, in: scrollView)
        waitFor(supplementsChart)
        forceTap(supplementsChart)

        let list = waitForIdentifier("Trends.SupplementDaySheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    private func chartElement(_ identifier: String) -> XCUIElement {
        let legacyChartElement = app.otherElements[identifier]
        if legacyChartElement.exists {
            return legacyChartElement
        }
        return app.buttons[identifier]
    }
}
