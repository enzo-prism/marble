import XCTest

final class EmpireFlowUITests: MarbleUITestCase {
    func testBuildFirstStructure() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.empire)
        waitForIdentifier("Empire.Scroll")

        // Balance is always visible at the top.
        waitForIdentifier("Empire.Balance")

        let buildQuarry = app.buttons["Empire.Build.quarry"]
        let scroll = app.scrollViews.firstMatch
        scrollToElement(buildQuarry, in: scroll, maxSwipes: 10)
        forceTap(buildQuarry)

        // Once built, the row shows a "Built" badge and the build button is gone.
        waitForIdentifier("Empire.Built.quarry")
        XCTAssertFalse(app.buttons["Empire.Build.quarry"].exists)
    }
}
