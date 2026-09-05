import XCTest

final class WorkoutHistoryUITests: MarbleUITestCase {
    func testRepeatWorkoutSupportsLargestAccessibilityText() {
        for appearance in [MarbleAppearance.light, MarbleAppearance.dark] {
            launchApp(
                appearance: appearance,
                contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                fixtureMode: "screenshots"
            )
            navigateToTab(.addWorkout)
            forceTap(waitForIdentifier("Workout.Open", timeout: 8))
            let finish = app.descendants(matching: .any).matching(identifier: "Workout.Finish").firstMatch
            scrollToElement(finish, in: app)
            forceTap(finish)
            forceTap(waitForIdentifier("Workout.Finish.Confirm"))
            let recent = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Recent.'")).firstMatch
            scrollToElement(recent, in: app)
            forceTap(recent)
            let repeatButton = waitForIdentifier("History.Repeat", timeout: 8)
            scrollToElement(repeatButton, in: app)
            XCTAssertTrue(repeatButton.isEnabled)
            XCTAssertTrue(repeatButton.isHittable)
            XCTAssertGreaterThanOrEqual(repeatButton.frame.height, 44)
            XCTAssertGreaterThan(repeatButton.frame.width, 100)
            takeScreenshot("History_Repeat_XXXL_\(appearance.envValue)")
            repeatButton.tap()
            XCTAssertTrue(waitForIdentifier("TextEntry.Title", timeout: 8).exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "TextEntry.Imported").firstMatch.exists,
                           "Opening a repeat at largest text must still wait for confirmation")
        }
    }

    func testCompletedSessionOpensEditableRepeatWithoutSaving() {
        launchApp(fixtureMode: "screenshots", extraEnvironment: ["MARBLE_ENABLE_REST_PILL": "1"])
        navigateToTab(.addWorkout)
        tapBottomAccessory(waitForIdentifier("SessionPill", timeout: 8))
        forceTap(waitForIdentifier("Workout.Finish", timeout: 8))
        forceTap(waitForIdentifier("Workout.Finish.Confirm"))
        let recent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Recent.'")).firstMatch
        waitFor(recent)
        forceTap(recent)
        let repeatButton = waitForIdentifier("History.Repeat", timeout: 8)
        XCTAssertTrue(repeatButton.isEnabled)
        forceTap(repeatButton)
        let title = waitForIdentifier("TextEntry.Title", timeout: 8)
        XCTAssertTrue(title.exists, "Repeat must open structured review without reparsing history")
        let originalTitle = title.value as? String ?? ""
        XCTAssertFalse(originalTitle.isEmpty)
        forceTap(title)
        title.typeText(" Copy")
        let importButton = waitForIdentifier("TextEntry.Import", timeout: 8)
        XCTAssertTrue(importButton.isEnabled)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "TextEntry.Imported").firstMatch.exists,
                       "Repeating must wait for explicit approval before saving")
        scrollToElement(importButton, in: app)
        forceTap(importButton)
        waitForIdentifier("TextEntry.Imported", timeout: 12)
        forceTap(waitForIdentifier("TextEntry.ImportedDone", timeout: 8))
        XCTAssertTrue(app.navigationBars[originalTitle].waitForExistence(timeout: 8),
                      "Saving the edited copy must leave the original session title unchanged")
    }

    func testEmptyHistoryDateFilterRemainsAccessible() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)
        forceTap(waitForIdentifier("Journal.WorkoutHistory", timeout: 8))
        forceTap(waitForIdentifier("History.FilterDate", timeout: 8))
        XCTAssertTrue(waitForIdentifier("History.Date", timeout: 8).exists)
        forceTap(waitForIdentifier("History.FilterDate"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "History.Date").firstMatch.exists)
    }
}
