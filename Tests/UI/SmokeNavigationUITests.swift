import XCTest

final class SmokeNavigationUITests: MarbleUITestCase {
    func testTabsPresentAndScreenshots() {
        launchApp(fixtureMode: "populated")

        let tabAnchors: [MarbleTab: String] = [
            .journal: "Journal.List",
            .calendar: "Calendar.View",
            .split: "Split.List",
            .supplements: "Supplements.List",
            .trends: "Trends.Scroll"
        ]

        for tab in MarbleTab.allCases {
            navigateToTab(tab)
            if let anchor = tabAnchors[tab] {
                waitForIdentifier(anchor, timeout: 8)
            }
            takeScreenshot("Tab_\(tab.rawValue)")
        }
    }
}
