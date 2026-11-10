import XCTest

final class TrendsSelectionUITests: MarbleUITestCase {
    func testTrendsConsistencySelectionOpensDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)
        revealDetailedTrends()

        let scrollView = app.scrollViews["Trends.Scroll"]
        let chart = chartElement("Trends.ConsistencyChart")
        scrollToElement(chart, in: scrollView)
        waitFor(chart)

        // 17 Pro can miss a single plot point (RC 42829580031). Tap, wait the
        // full sheet timeout, then try another x offset only if the list never
        // appeared — a short wait can tap an opening sheet and dismiss it.
        let list = app.descendants(matching: .any).matching(identifier: "Trends.DaySheet.List").firstMatch
        for offset in [0.9, 0.75, 0.6, 0.45] as [CGFloat] {
            tapVisible(chart, normalizedOffset: CGVector(dx: offset, dy: 0.5))
            if list.waitForExistence(timeout: 6) { break }
        }
        XCTAssertTrue(list.exists, "Consistency chart tap should open the day sheet")
    }

    func testTrendsWeeklyVolumeSelectionOpensWeekDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)
        revealDetailedTrends()

        let scrollView = app.scrollViews["Trends.Scroll"]
        let volumeChart = chartElement("Trends.VolumeChart")
        // The coaching sections above the chart make the page taller than a
        // few blind swipes; scroll until the chart is actually on screen so
        // the normalized-coordinate tap lands inside the plot.
        scrollToElement(volumeChart, in: scrollView)
        waitFor(volumeChart)

        tapVisible(volumeChart, normalizedOffset: CGVector(dx: 0.8, dy: 0.4))

        let list = waitForIdentifier("Trends.WeekSheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    func testTrendsSupplementsSelectionOpensSupplementDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)
        revealDetailedTrends()

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
