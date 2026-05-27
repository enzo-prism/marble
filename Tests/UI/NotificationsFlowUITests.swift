import XCTest

final class NotificationsFlowUITests: MarbleUITestCase {
    func testCreateEditDisableDeleteNotification() {
        launchApp(fixtureMode: "empty")
        openNotifications()

        app.buttons["Notifications.Add"].tap()
        waitFor(app.navigationBars["New Notification"], timeout: 5)

        let messageField = textInput("NotificationEditor.Message")
        waitFor(messageField)
        messageField.tap()
        messageField.typeText("Log workout")
        app.buttons["NotificationEditor.Save"].tap()

        let list = waitForIdentifier("Notifications.List", timeout: 5)
        XCTAssertTrue(app.staticTexts["Log workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(notificationRows(in: list).firstMatch.exists)

        notificationRows(in: list).firstMatch.tap()
        waitFor(app.navigationBars["Edit Notification"], timeout: 5)
        let editField = textInput("NotificationEditor.Message")
        waitFor(editField)
        clearAndType(editField, text: "Edited reminder")
        app.buttons["NotificationEditor.Save"].tap()

        XCTAssertTrue(app.staticTexts["Edited reminder"].waitForExistence(timeout: 5))

        let toggle = notificationToggles().firstMatch
        waitFor(toggle)
        toggle.tap()

        notificationRows(in: list).firstMatch.tap()
        waitFor(app.navigationBars["Edit Notification"], timeout: 5)
        app.buttons["NotificationEditor.Delete"].tap()
        let confirmDelete = app.buttons["NotificationEditor.ConfirmDelete"].firstMatch
        waitFor(confirmDelete)
        confirmDelete.tap()

        XCTAssertTrue(app.staticTexts["No notifications"].waitForExistence(timeout: 5))
    }

    func testMaxTenNotificationsDisablesAdd() {
        launchApp(fixtureMode: "empty")
        openNotifications()

        for index in 1...CustomNotificationTestValues.maximumCount {
            app.buttons["Notifications.Add"].tap()
            waitFor(app.navigationBars["New Notification"], timeout: 5)
            let messageField = textInput("NotificationEditor.Message")
            waitFor(messageField)
            messageField.tap()
            messageField.typeText("Reminder \(index)")
            app.buttons["NotificationEditor.Save"].tap()
            XCTAssertTrue(app.staticTexts["Reminder \(index)"].waitForExistence(timeout: 5))
        }

        let addButton = app.buttons["Notifications.Add"]
        waitFor(addButton)
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertTrue(app.staticTexts["10 notification limit reached."].exists)
    }

    func testDeniedPermissionShowsSettingsState() {
        launchApp(fixtureMode: "empty", notificationAuthorization: "denied")
        openNotifications()

        waitForIdentifier("Notifications.Permission.Title")
        XCTAssertTrue(app.buttons["Notifications.Permission.Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notifications Off"].waitForExistence(timeout: 5))
    }

    private func openNotifications() {
        navigateToTab(.journal)
        let button = app.buttons["Journal.Notifications"]
        waitFor(button)
        button.tap()
        waitForIdentifier("Notifications.List", timeout: 5)
    }

    private func notificationRows(in list: XCUIElement) -> XCUIElementQuery {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Notifications.Row.")
        let scoped = list.descendants(matching: .any).matching(predicate)
        if scoped.count > 0 {
            return scoped
        }
        return app.descendants(matching: .any).matching(predicate)
    }

    private func notificationToggles() -> XCUIElementQuery {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Notifications.Toggle.")
        let switches = app.switches.matching(predicate)
        if switches.count > 0 {
            return switches
        }
        return app.descendants(matching: .any).matching(predicate)
    }
}

private enum CustomNotificationTestValues {
    static let maximumCount = 10
}
