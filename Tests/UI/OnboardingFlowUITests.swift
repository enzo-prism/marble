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

    private var onboardingList: XCUIElement {
        let collection = app.collectionViews.firstMatch
        if collection.exists { return collection }
        let table = app.tables.firstMatch
        return table.exists ? table : app
    }

    /// List rows in the onboarding cover are below the fold until scrolled.
    private func reveal(_ identifier: String, timeout: TimeInterval = 20) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if element.waitForExistence(timeout: timeout), element.isHittable {
            return element
        }
        scrollToElement(element, in: onboardingList)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing Onboarding control: \(identifier)")
        return element
    }

    private func waitForMainApp() {
        waitForDisappearance(app.buttons["Onboarding.Done"], timeout: 10)
        // SwiftUI can drop tab-item identifiers after a full-screen cover
        // dismisses. The actual Log button remains visible and tappable.
        let journal = app.tabBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "Tab.Journal", "Log"
        )).firstMatch
        waitFor(journal, timeout: 10)
        XCTAssertTrue(journal.isHittable)
    }

    func testOnboardingWalksThreePagesAndHandsOverToTheApp() {
        launchOnboarding()

        step("Welcome page shows Continue, not Get Started") {
            waitForIdentifier("Onboarding.Continue", timeout: 10)
            XCTAssertFalse(app.buttons["Onboarding.Done"].exists)
        }

        step("Advance to the weekly goal page") {
            forceTap(app.buttons["Onboarding.Continue"])
            _ = reveal("Onboarding.WeeklyTarget")
        }

        step("Advance to the weight unit page — the last one") {
            forceTap(app.buttons["Onboarding.Continue"])
            _ = reveal("Onboarding.WeightUnit")
            waitForIdentifier("Onboarding.Done", timeout: 8)
        }

        step("Finishing reveals the app itself") {
            forceTap(app.buttons["Onboarding.Done"])
            // A tappable app tab plus the dismissed cover proves the gate let go.
            waitForMainApp()
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

        let unitPicker = reveal("Onboarding.WeightUnit")
        let kg = unitPicker.buttons["kg"]
        if kg.waitForExistence(timeout: 4) {
            forceTap(kg)
        } else {
            XCTFail("The onboarding unit picker offers no kg option")
            return
        }

        forceTap(waitForIdentifier("Onboarding.Done", timeout: 8))
        waitForMainApp()

        navigateToTab(.addWorkout)
        openAddToolbarAction("Workout.Settings")

        let settingsUnit = reveal("Settings.WeightUnit")
        XCTAssertTrue(
            settingsUnit.buttons["kg"].isSelected,
            "Settings must show the unit chosen during onboarding — both read the same key"
        )
    }
}
