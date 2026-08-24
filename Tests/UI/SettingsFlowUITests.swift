import XCTest

/// The Settings smoke test Phase 1E promised: every row on the screen that
/// consolidates Marble's preferences, plus the new Body section that makes a
/// weigh-in correctable.
///
/// Settings rows live in a `List`, so anything below the fold is absent from the
/// accessibility tree until scrolled — `scrollToElement` first, every time (the
/// documented 2.2 lesson).
final class SettingsFlowUITests: MarbleUITestCase {
    private func openSettings() {
        launchApp()
        navigateToTab(.addWorkout)
        openAddToolbarAction("Workout.Settings")
        waitForIdentifier("Settings.Done", timeout: 8)
    }

    private var settingsList: XCUIElement {
        let collection = app.collectionViews.firstMatch
        return collection.exists ? collection : app
    }

    private func reveal(_ identifier: String, timeout: TimeInterval = 8) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if element.waitForExistence(timeout: timeout), element.isHittable {
            return element
        }
        scrollToElement(element, in: settingsList)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing Settings row: \(identifier)")
        return element
    }

    func testSettingsShowsEveryPreferenceSection() {
        openSettings()

        step("Units + Training") {
            waitForIdentifier("Settings.WeightUnit", timeout: 8)
            waitForIdentifier("Settings.WeeklyTarget", timeout: 8)
            _ = reveal("Settings.DailyHighlights")
        }

        step("Body — the 2.4 gap this release closes") {
            _ = reveal("Settings.DotsCoefficients")
            _ = reveal("Settings.LogWeight")
            _ = reveal("Settings.WeighIns")
        }

        step("Notifications, Health, Data, About") {
            _ = reveal("Settings.WeeklyGoalReminder")
            _ = reveal("Settings.HealthAutoImport")
            _ = reveal("Settings.HealthBodyMetrics")
            _ = reveal("Settings.Data")
            _ = reveal("Settings.Version")
        }

        step("Done dismisses") {
            forceTap(app.buttons["Settings.Done"])
            waitForDisappearance(app.buttons["Settings.Done"])
        }
    }

    /// The whole point of the Body section: a weigh-in can be logged and then
    /// corrected or removed. Before this release `BodyMetricEntryView` was only
    /// ever presented with `nil`, so a typo was permanent.
    func testWeighInCanBeLoggedThenDeleted() {
        openSettings()

        step("Log a weigh-in from Settings") {
            forceTap(reveal("Settings.LogWeight"))
            let field = waitForIdentifier("BodyMetricEntry.Weight", timeout: 8)
            forceTap(field)
            field.typeText("182")
            dismissKeyboardIfPresent()
            forceTap(waitForIdentifier("BodyMetricEntry.Save", timeout: 8))
        }

        step("It appears in the weigh-in history") {
            forceTap(reveal("Settings.WeighIns"))
            waitForIdentifier("BodyMetricHistory.List", timeout: 8)
            XCTAssertFalse(
                app.descendants(matching: .any).matching(identifier: "BodyMetricHistory.EmptyState").firstMatch.exists,
                "A logged weigh-in must not leave the history empty"
            )
        }

        step("A swipe deletes it, leaving the empty state") {
            let list = app.collectionViews.firstMatch
            let row = list.cells.element(boundBy: 0)
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            row.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 4) {
                forceTap(delete)
            } else {
                XCTFail("No Delete action after swiping a weigh-in")
                return
            }
            waitForIdentifier("BodyMetricHistory.EmptyState", timeout: 8)
        }
    }
}
