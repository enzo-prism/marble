import XCTest

final class SmokeNavigationUITests: MarbleUITestCase {
    func testTabsPresentAndScreenshots() {
        launchApp(fixtureMode: "populated")

        let tabs: [MarbleTab] = [.journal, .calendar, .supplements, .trends]
        for tab in tabs {
            navigateToTab(tab)
            takeScreenshot("Tab_\(tab.rawValue)")
        }
    }
}
