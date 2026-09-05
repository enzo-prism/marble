import XCTest

final class DraftResumeUITests: MarbleUITestCase {
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
