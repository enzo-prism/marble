import XCTest

/// Exercises the in-app rest pill (the tab-bar bottom accessory). The pill is
/// disabled during UI tests by default so it can't overlay unrelated flows;
/// these tests opt back in via `MARBLE_ENABLE_REST_PILL`.
///
/// Launches with a *real* `now`: the pill's countdown and auto-end run on the
/// wall clock, so the frozen test date would make every rest start expired.
final class RestTimerPillUITests: MarbleUITestCase {
    func testRestPillAppearsOnLogAgainAndEndsOnTap() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        launchApp(
            nowISO8601: formatter.string(from: Date()),
            extraEnvironment: ["MARBLE_ENABLE_REST_PILL": "1"]
        )

        step("Log the latest set again to start its 60 s rest timer") {
            let logAgain = waitForIdentifier("Journal.QuickLog.LogAgain", timeout: 8)
            forceTap(logAgain)
        }

        let pill = app.descendants(matching: .any).matching(identifier: "RestPill").firstMatch
        step("The rest pill appears above the tab bar") {
            waitFor(pill, timeout: 6)
        }

        step("Ending the rest dismisses the pill") {
            let endButton = app.buttons["RestPill.End"]
            waitFor(endButton)
            forceTap(endButton)
            waitForDisappearance(pill, timeout: 6)
        }
    }
}
