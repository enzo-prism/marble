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
            _ = waitForIdentifier("TextEntry.ReviewSummary", timeout: 15)

            let date = app.descendants(matching: .any).matching(identifier: "TextEntry.Date").firstMatch
            scrollToElement(date, in: app.collectionViews.firstMatch)
            waitFor(date, timeout: 10)
            revealAboveSave(date)
            let dateLabel = app.staticTexts["Date"].firstMatch
            waitFor(dateLabel)
            XCTAssertTrue(dateLabel.isHittable, "The date label must remain visible at largest text")
            XCTAssertTrue(date.isEnabled)
            XCTAssertTrue(date.isHittable)
            XCTAssertFalse(dateLabel.frame.intersects(date.frame), "The date control must not cover its label")
            // The native compact DatePicker exposes its displayed date on its
            // child button; the DatePicker container itself has an empty value.
            let dateButton = date.buttons.firstMatch
            waitFor(dateButton)
            XCTAssertTrue(dateButton.isHittable)
            let reviewedDate = try XCTUnwrap(dateButton.value as? String)
            XCTAssertFalse(reviewedDate.isEmpty)
            takeScreenshot("Composer_Date_XXXL_\(appearance.envValue)")
            dateButton.tap()
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
            let restoredDate = app.descendants(matching: .any).matching(identifier: "TextEntry.Date").firstMatch
            scrollToElement(restoredDate, in: app.collectionViews.firstMatch)
            waitFor(restoredDate, timeout: 10)
            revealAboveSave(restoredDate)
            let restoredDateButton = restoredDate.buttons.firstMatch
            waitFor(restoredDateButton)
            XCTAssertEqual(restoredDateButton.value as? String, reviewedDate)

            let includeTime = app.switches["TextEntry.IncludeTime"]
            scrollToElement(includeTime, in: app.collectionViews.firstMatch)
            waitFor(includeTime)
            XCTAssertTrue(includeTime.isHittable)
            XCTAssertEqual(includeTime.value as? String, "0")
            // SwiftUI exposes the whole multiline label as a Switch wrapper.
            // Its center is outside the native switch, so tap that child directly.
            let nativeSwitch = includeTime.switches.firstMatch
            waitFor(nativeSwitch)
            forceTap(nativeSwitch)
            let enabled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == '1'"), object: includeTime
            )
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            let time = app.descendants(matching: .any).matching(identifier: "TextEntry.Time").firstMatch
            scrollToElement(time, in: app.collectionViews.firstMatch)
            waitFor(time, timeout: 8)
            revealAboveSave(time)
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

    private func revealAboveSave(_ element: XCUIElement) {
        let save = app.buttons["TextEntry.Import"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where element.frame.maxY > save.frame.minY - 8 {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, save.frame.minY - 8,
                                 "The entire closed picker must fit above the save action")
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

    func testReviewedWeightAndDateSurviveTermination() throws {
        let environment = ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString]
        launchApp(fixtureMode: "empty", extraEnvironment: environment)
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Yesterday: Push\nBench Press 1x8 @ 185 lb")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
        let date = app.descendants(matching: .any).matching(identifier: "TextEntry.Date").firstMatch
        scrollToElement(date, in: app.collectionViews.firstMatch)
        waitFor(date, timeout: 10)
        let dateButton = date.buttons.firstMatch
        waitFor(dateButton)
        let reviewedDate = try XCTUnwrap(dateButton.value as? String)
        XCTAssertFalse(reviewedDate.isEmpty)
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
        let restoredDate = app.descendants(matching: .any).matching(identifier: "TextEntry.Date").firstMatch
        scrollToElement(restoredDate, in: app.collectionViews.firstMatch)
        waitFor(restoredDate, timeout: 8)
        XCTAssertEqual(restoredDate.buttons.firstMatch.value as? String, reviewedDate)
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
