import XCTest

final class LogModePickerUITests: MarbleUITestCase {
    func testLogModesRemainDistinctAndUsableAtLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated",
            extraEnvironment: ["MARBLE_INITIAL_TAB": "journal"]
        )

        let menu = app.buttons["Log.Mode.Menu"]
        waitFor(menu, timeout: 8)
        XCTAssertTrue(menu.isHittable)
        XCTAssertTrue(menu.label.contains("Sets"))

        forceTap(menu)
        forceTap(modeButton("Tab.Calendar"))
        waitForIdentifier("Calendar.View", timeout: 8)
        XCTAssertTrue(app.buttons["Log.Mode.Menu"].label.contains("Calendar"))

        forceTap(app.buttons["Log.Mode.Menu"])
        forceTap(modeButton("Tab.Supplements"))
        waitForIdentifier("Supplements.List", timeout: 8)
        XCTAssertTrue(app.buttons["Log.Mode.Menu"].label.contains("Supplements"))
    }

    private func modeButton(
        _ identifier: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCUIElement {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        waitFor(button, timeout: 8, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        XCTAssertGreaterThan(button.frame.height, 0, file: file, line: line)
        return button
    }
}
