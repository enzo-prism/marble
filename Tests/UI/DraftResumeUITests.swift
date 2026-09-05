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
            revealAboveSave(date, label: app.staticTexts["Date"].firstMatch)
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
            revealAboveSave(restoredDate, label: app.staticTexts["Date"].firstMatch)
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
            XCTAssertEqual(includeTime.value as? String, "1")
            // Inspect the switch while its lazy row is visible. Revealing the
            // full picker can legitimately scroll that row out of the tree.
            let time = app.descendants(matching: .any).matching(identifier: "TextEntry.Time").firstMatch
            scrollToElement(time, in: app.collectionViews.firstMatch)
            waitFor(time, timeout: 8)
            revealAboveSave(time, label: app.staticTexts["Time"].firstMatch)
            let timeLabel = app.staticTexts["Time"].firstMatch
            waitFor(timeLabel)
            XCTAssertTrue(timeLabel.isHittable, "The time label must remain visible at largest text")
            XCTAssertTrue(time.isEnabled)
            XCTAssertTrue(time.isHittable)
            XCTAssertFalse(timeLabel.frame.intersects(time.frame), "The time control must not cover its label")
            takeScreenshot("Composer_Time_XXXL_\(appearance.envValue)")
            time.tap()
            takeScreenshot("Composer_TimePicker_Open_XXXL_\(appearance.envValue)")
        }
    }

    private func revealAboveSave(_ element: XCUIElement, label: XCUIElement) {
        let save = app.buttons["TextEntry.Import"]
        let list = app.collectionViews.firstMatch
        let navigation = app.navigationBars.firstMatch
        func bounds() -> CGRect {
            label.exists ? element.frame.union(label.frame) : element.frame
        }
        for _ in 0..<10 {
            let top = max(list.frame.minY, navigation.frame.maxY) + 12
            let bottom = min(list.frame.maxY, save.frame.minY) - 12
            let frame = bounds()
            if frame.minY >= top && frame.maxY <= bottom { break }
            // A full swipe can overshoot a compact Date/Time row at XXXL.
            // Correct in either direction, using short, measured drags so both
            // the label and complete native value fit inside the viewport.
            let delta = frame.minY < top ? frame.minY - top : frame.maxY - bottom
            let requested = delta / list.frame.height
            // Keep the drag larger than touch slop; a few-pixel movement can
            // be interpreted as a tap on the content instead of a scroll.
            let fraction = requested < 0
                ? max(-0.22, min(-0.06, requested))
                : min(0.22, max(0.06, requested))
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05,
                       thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 - fraction)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertGreaterThanOrEqual(bounds().minY, max(list.frame.minY, navigation.frame.maxY) + 8,
                                    "The label and picker must remain below navigation")
        XCTAssertLessThanOrEqual(bounds().maxY, min(list.frame.maxY, save.frame.minY) - 8,
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
