import XCTest

/// The onboarding test Phase 1E promised and 2.2 shipped without: the
/// `MARBLE_FORCE_ONBOARDING` hook existed in the app and had no references in
/// `Tests/` outside the screenshot capture, so nothing verified that first run
/// actually presents, advances, records its two preferences, and hands over to
/// the app.
///
/// Onboarding is force-enabled here because it is suppressed under UI testing by
/// default — it would otherwise block every other flow, which launch against a
/// fresh store.
final class OnboardingFlowUITests: MarbleUITestCase {
    private func launchOnboarding() {
        launchApp(
            fixtureMode: "empty",
            extraEnvironment: ["MARBLE_FORCE_ONBOARDING": "1"]
        )
    }

    func testOnboardingWalksThreePagesAndHandsOverToTheApp() {
        launchOnboarding()

        step("Welcome page shows Continue, not Get Started") {
            waitForIdentifier("Onboarding.Continue", timeout: 10)
            XCTAssertFalse(app.buttons["Onboarding.Done"].exists)
        }

        step("Advance to the weekly goal page") {
            forceTap(app.buttons["Onboarding.Continue"])
            waitForIdentifier("Onboarding.WeeklyTarget", timeout: 8)
        }

        step("Advance to the weight unit page — the last one") {
            forceTap(app.buttons["Onboarding.Continue"])
            waitForIdentifier("Onboarding.WeightUnit", timeout: 8)
            waitForIdentifier("Onboarding.Done", timeout: 8)
        }

        step("Finishing reveals the app itself") {
            forceTap(app.buttons["Onboarding.Done"])
            // The Journal tab existing at all proves the gate let go: onboarding
            // is presented full-screen with dismissal disabled.
            waitForIdentifier("Tab.Journal", timeout: 10)
            XCTAssertFalse(app.buttons["Onboarding.Done"].exists)
        }
    }

    /// The preference pages write straight through as the user picks, so the
    /// choice has to survive into the app — this is the half of onboarding that
    /// silently does nothing if the bindings are wrong.
    func testWeightUnitChosenDuringOnboardingReachesSettings() {
        launchOnboarding()

        forceTap(waitForIdentifier("Onboarding.Continue", timeout: 10))
        forceTap(waitForIdentifier("Onboarding.Continue", timeout: 8))

        let unitPicker = waitForIdentifier("Onboarding.WeightUnit", timeout: 8)
        let kg = unitPicker.buttons["kg"]
        if kg.waitForExistence(timeout: 4) {
            forceTap(kg)
        } else {
            XCTFail("The onboarding unit picker offers no kg option")
            return
        }

        forceTap(waitForIdentifier("Onboarding.Done", timeout: 8))
        waitForIdentifier("Tab.Journal", timeout: 10)

        navigateToTab(.addWorkout)
        openAddToolbarAction("Workout.Settings")

        let settingsUnit = waitForIdentifier("Settings.WeightUnit", timeout: 8)
        XCTAssertTrue(
            settingsUnit.buttons["kg"].isSelected,
            "Settings must show the unit chosen during onboarding — both read the same key"
        )
    }
}
