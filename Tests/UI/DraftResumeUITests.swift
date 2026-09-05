import XCTest

final class DraftResumeUITests: MarbleUITestCase {
    func testLargestTextDateAndTimeControlsRemainReachable() throws {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        for appearance in [MarbleAppearance.light, MarbleAppearance.dark] {
            let environment = ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString]
            launchApp(
                appearance: appearance, contentSizeCategory: category,
                fixtureMode: "empty", extraEnvironment: environment
            )
            let editor = waitForIdentifier("TextEntry.Editor", timeout: 8)
            editor.tap()
            editor.typeText("Yesterday: Push\nBench Press 1x8 @ 185 lb")
            dismissKeyboardIfPresent()
            let preview = app.descendants(matching: .any).matching(identifier: "TextEntry.Preview").firstMatch
            scrollToElement(preview, in: app)
            forceTap(preview)

            let date = waitForIdentifier("TextEntry.Date", timeout: 10)
            scrollToElement(date, in: app.collectionViews.firstMatch)
            let dateLabel = app.staticTexts["Date"].firstMatch
            waitFor(dateLabel)
            XCTAssertTrue(dateLabel.isHittable, "The date label must remain visible at largest text")
            XCTAssertTrue(date.isEnabled)
            XCTAssertTrue(date.isHittable)
            XCTAssertFalse(dateLabel.frame.intersects(date.frame), "The date control must not cover its label")
            let reviewedDate = try XCTUnwrap(date.value as? String)
            XCTAssertFalse(reviewedDate.isEmpty)
            takeScreenshot("Composer_Date_XXXL_\(appearance.envValue)")
            date.tap()
            takeScreenshot("Composer_DatePicker_Open_XXXL_\(appearance.envValue)")

            // Opening the native picker must not change the parsed workout date.
            // Relaunch also closes its popover without relying on system button
            // titles, calendar formatting, or a hard-coded dismissal coordinate.
            XCUIDevice.shared.press(.home)
            app.terminate()
            launchApp(
                appearance: appearance, contentSizeCategory: category,
                fixtureMode: "empty", resetDB: false, extraEnvironment: environment
            )
            let resume = app.buttons["WorkoutEntry.Draft.Resume"]
            scrollToElement(resume, in: app)
            forceTap(resume)
            let restoredDate = waitForIdentifier("TextEntry.Date", timeout: 10)
            scrollToElement(restoredDate, in: app.collectionViews.firstMatch)
            XCTAssertEqual(restoredDate.value as? String, reviewedDate)

            let includeTime = app.switches["TextEntry.IncludeTime"]
            scrollToElement(includeTime, in: app.collectionViews.firstMatch)
            waitFor(includeTime)
            XCTAssertTrue(includeTime.isHittable)
            XCTAssertEqual(includeTime.value as? String, "0")
            includeTime.tap()
            let time = waitForIdentifier("TextEntry.Time", timeout: 8)
            scrollToElement(time, in: app.collectionViews.firstMatch)
            let timeLabel = app.staticTexts["Time"].firstMatch
            waitFor(timeLabel)
            XCTAssertTrue(timeLabel.isHittable, "The time label must remain visible at largest text")
            XCTAssertTrue(time.isEnabled)
            XCTAssertTrue(time.isHittable)
            XCTAssertFalse(timeLabel.frame.intersects(time.frame), "The time control must not cover its label")
            XCTAssertEqual(includeTime.value as? String, "1")
            takeScreenshot("Composer_Time_XXXL_\(appearance.envValue)")
            time.tap()
            takeScreenshot("Composer_TimePicker_Open_XXXL_\(appearance.envValue)")
        }
    }

    func testLargeTextRecoveryActionsRemainReachable() {
        let environment = ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString]
        launchApp(fixtureMode: "empty", extraEnvironment: environment)
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Bench Press 3x8")
        XCUIDevice.shared.press(.home)
        app.terminate()
        launchApp(
            appearance: .dark,
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "empty", resetDB: false, extraEnvironment: environment
        )
        let resume = app.buttons["WorkoutEntry.Draft.Resume"]
        scrollToElement(resume, in: app)
        waitFor(resume, timeout: 8)
        forceTap(resume)
        XCTAssertTrue(waitForIdentifier("TextEntry.Editor", timeout: 8).exists)
    }

    func testReviewedWeightAndDateSurviveTermination() {
        let environment = ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString]
        launchApp(fixtureMode: "empty", extraEnvironment: environment)
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Yesterday: Push\nBench Press 1x8 @ 185 lb")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
        let date = waitForIdentifier("TextEntry.Date", timeout: 10)
        let reviewedDate = date.value as? String
        XCTAssertNotNil(reviewedDate)
        let weight = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'TextEntry.Set.Weight.'")).firstMatch
        scrollToElement(weight, in: app.collectionViews.firstMatch)
        waitFor(weight, timeout: 8)
        clearAndType(weight, text: "195")
        let weightID = weight.identifier
        dismissKeyboardIfPresent()
        // Backgrounding flushes pending edits before the termination boundary.
        XCUIDevice.shared.press(.home)
        app.terminate()
        launchApp(fixtureMode: "empty", resetDB: false, extraEnvironment: environment)
        forceTap(waitForIdentifier("WorkoutEntry.Draft.Resume", timeout: 10))
        XCTAssertEqual(waitForIdentifier("TextEntry.Date", timeout: 8).value as? String, reviewedDate)
        let restoredWeight = app.textFields[weightID]
        scrollToElement(restoredWeight, in: app.collectionViews.firstMatch)
        XCTAssertEqual(restoredWeight.value as? String, "195")
    }

    func testDiscardedDraftDoesNotReturnAfterRelaunch() {
        let environment = ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString]
        launchApp(fixtureMode: "empty", extraEnvironment: environment)
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Bench Press 3x8")
        XCUIDevice.shared.press(.home)
        app.terminate()
        launchApp(fixtureMode: "empty", resetDB: false, extraEnvironment: environment)
        forceTap(waitForIdentifier("WorkoutEntry.Draft.Discard", timeout: 10))
        forceTap(app.buttons.matching(identifier: "WorkoutEntry.Draft.ConfirmDiscard").firstMatch)
        XCUIDevice.shared.press(.home)
        app.terminate()
        launchApp(fixtureMode: "empty", resetDB: false, extraEnvironment: environment)
        XCTAssertTrue(waitForIdentifier("TextEntry.Editor", timeout: 8).exists)
        XCTAssertFalse(app.buttons["WorkoutEntry.Draft.Resume"].exists)
    }
}
