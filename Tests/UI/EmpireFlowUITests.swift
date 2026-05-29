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

    func testClaimDailyTribute() {
        // The populated fixture logs sets on the current day, so today's Tribute is claimable.
        launchApp(fixtureMode: "populated")
        navigateToTab(.empire)
        waitForIdentifier("Empire.Scroll")

        let claim = app.buttons["Empire.Tribute.Claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: 5))
        forceTap(claim)

        // The reveal appears; collect the reward.
        let collect = app.buttons["Empire.Tribute.Collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 5))
        forceTap(collect)

        // Today's Tribute is spent: the card stays but the Claim button is gone.
        waitForIdentifier("Empire.Tribute")
        XCTAssertFalse(app.buttons["Empire.Tribute.Claim"].exists)
    }
}
