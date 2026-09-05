import XCTest

final class PersistenceRecoveryUITests: MarbleUITestCase {
    func testUnavailableStorageBlocksLoggingAndRetryRestoresApp() {
        launchApp(fixtureMode: "empty", extraEnvironment: ["MARBLE_TEST_STORAGE_FAILURE": "1"])
        XCTAssertTrue(waitForIdentifier("Storage.Unavailable.Title", timeout: 8).exists)
        XCTAssertFalse(app.textViews["TextEntry.Editor"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        forceTap(waitForIdentifier("Storage.Retry"))
        XCTAssertTrue(waitForIdentifier("TextEntry.Editor", timeout: 8).exists)
        XCTAssertFalse(app.staticTexts["Storage.Unavailable.Title"].exists)
    }

    func testUnavailableStorageAccessibility() throws {
        launchApp(appearance: .dark, fixtureMode: "empty", accessibilityAudit: true,
                  extraEnvironment: ["MARBLE_TEST_STORAGE_FAILURE": "1"])
        XCTAssertTrue(waitForIdentifier("Storage.Unavailable.Title", timeout: 8).exists)
        try app.performAccessibilityAudit()
    }
}
