import XCTest

final class TrendsSelectionUITests: MarbleUITestCase {
    func testTrendsConsistencySelectionOpensDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let chart = app.otherElements["Trends.ConsistencyChart"]
        waitFor(chart)

        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let list = waitForIdentifier("Trends.DaySheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    func testTrendsWeeklyVolumeSelectionOpensWeekDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let scrollView = app.scrollViews["Trends.Scroll"]
        let volumeChart = app.otherElements["Trends.VolumeChart"]
        if !volumeChart.exists {
            for _ in 0..<3 {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
                if volumeChart.exists {
                    break
                }
            }
        }
        waitFor(volumeChart)

        volumeChart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)).tap()

        let list = waitForIdentifier("Trends.WeekSheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }

    func testTrendsSupplementsSelectionOpensSupplementDayDetails() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let scrollView = app.scrollViews["Trends.Scroll"]
        let supplementsChart = app.otherElements["Trends.SupplementsChart"]
        scrollToElement(supplementsChart, in: scrollView)
        waitFor(supplementsChart)
        forceTap(supplementsChart)

        let list = waitForIdentifier("Trends.SupplementDaySheet.List", timeout: 6)
        XCTAssertTrue(list.exists)
    }
}
