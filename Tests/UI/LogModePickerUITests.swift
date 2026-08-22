import XCTest

final class LogModePickerUITests: MarbleUITestCase {
    func testLogModesRemainDistinctAndUsableAtLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated",
            extraEnvironment: ["MARBLE_INITIAL_TAB": "journal"]
        )

        let sets = modeButton("Log.Mode.Sets")
        let calendar = modeButton("Tab.Calendar")
        let supplements = modeButton("Tab.Supplements")

        XCTAssertEqual(sets.label, "Sets")
        XCTAssertEqual(calendar.label, "Calendar")
        XCTAssertEqual(supplements.label, "Supplements")
        XCTAssertLessThanOrEqual(sets.frame.maxY, calendar.frame.minY)
        XCTAssertLessThanOrEqual(calendar.frame.maxY, supplements.frame.minY)

        forceTap(calendar)
        waitForIdentifier("Calendar.View", timeout: 8)

        forceTap(modeButton("Tab.Supplements"))
        waitForIdentifier("Supplements.List", timeout: 8)
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
