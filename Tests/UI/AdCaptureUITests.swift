import UIKit
import XCTest

/// Drives a slow, watchable tour of the app seeded with the rich `showcase` dataset
/// (and no test chrome) so an external recorder (`xcrun simctl io … recordVideo`) can
/// capture real interaction footage for marketing. This is a capture tool, not a
/// pass/fail regression test — every interaction is best-effort and never asserts.
///
/// Capture: see `scripts/capture_showcase_recording.sh`.
final class AdCaptureUITests: XCTestCase {
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MARBLE_SHOWCASE": "1",
            "MARBLE_FORCE_COLOR_SCHEME": "dark",
            "MARBLE_NOW_ISO8601": "2025-01-15T12:00:00Z",
            "MARBLE_DISABLE_ANIMATIONS": "1"
        ]
        app.launch()

        func wait(_ seconds: TimeInterval = 0.8) {
            Thread.sleep(forTimeInterval: seconds)
        }

        func save(_ name: String) throws {
            let family = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            let outputDirectory = ProcessInfo.processInfo.environment["MARBLE_SCREENSHOT_DIR"] ??
                "/Users/enzo/Projects/marble/marketing/app-store/1.8/raw/\(family)"
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: outputDirectory),
                withIntermediateDirectories: true
            )
            let screenshot = XCUIScreen.main.screenshot()
            let fileURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(name).png")
            try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)

            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func tapTab(identifier: String, label: String) {
            let candidates = [
                app.tabBars.buttons.matching(identifier: label).element(boundBy: 0),
                app.buttons.matching(identifier: identifier).element(boundBy: 0),
                app.buttons.matching(NSPredicate(format: "label == %@", label)).element(boundBy: 0),
                app.otherElements.matching(identifier: identifier).element(boundBy: 0)
            ]
            for candidate in candidates where candidate.waitForExistence(timeout: 2) {
                if candidate.isHittable {
                    candidate.tap()
                } else {
                    candidate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                return
            }
        }

        _ = app.buttons["QuickLog.Button"].waitForExistence(timeout: 8)
        wait(1.0)
        try save("01-journal")

        let quickLog = app.buttons["QuickLog.Button"]
        if quickLog.waitForExistence(timeout: 5) {
            quickLog.tap()
            _ = app.navigationBars["Log Set"].waitForExistence(timeout: 5)
            wait()
            try save("02-log-set")
            app.swipeDown(velocity: .fast)
            wait()
        }

        tapTab(identifier: "Tab.Calendar", label: "Calendar")
        _ = app.otherElements["Calendar.View"].waitForExistence(timeout: 8)
        wait(1.0)
        try save("03-calendar")

        tapTab(identifier: "Tab.Supplements", label: "Supplements")
        _ = app.otherElements["Supplements.List"].waitForExistence(timeout: 8)
        wait(1.0)
        try save("04-supplements")

        tapTab(identifier: "Tab.Trends", label: "Trends")
        _ = app.otherElements["Trends.Scroll"].waitForExistence(timeout: 8)
        wait(1.0)
        try save("05-trends")
    }

    func testShowcaseTour() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MARBLE_SHOWCASE": "1",
            "MARBLE_FORCE_COLOR_SCHEME": "dark",
            "MARBLE_NOW_ISO8601": "2025-01-15T12:00:00Z"
        ]
        app.launch()

        func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
        func tab(_ name: String) {
            let button = app.tabBars.buttons[name]
            if button.waitForExistence(timeout: 4) { button.tap() }
        }

        // 1 — Journal: let the "Ready to log" hero + today's sets settle, then browse history.
        pause(2.0)
        app.swipeUp(); pause(1.2)
        app.swipeUp(); pause(1.0)
        app.swipeDown(); pause(0.8)
        app.swipeDown(); pause(1.0)

        // 2 — Calendar: open a logged day to reveal the day sheet.
        tab("Calendar"); pause(1.8)
        let calendar = app.otherElements["Calendar.View"]
        if calendar.waitForExistence(timeout: 3) {
            let day = calendar.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "8", "8 "))
                .firstMatch
            if day.waitForExistence(timeout: 2) {
                day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(2.6)
                app.swipeDown(velocity: .fast); pause(1.0)
            }
        }

        // 3 — Trends: cycle the range so the charts redraw.
        tab("Trends"); pause(1.8)
        for range in ["90D", "1Y", "30D"] {
            let button = app.buttons[range]
            if button.exists { button.tap(); pause(1.4) }
        }
        app.swipeUp(); pause(1.2)
        app.swipeDown(); pause(0.8)

        // 4 — Supplements.
        tab("Supplements"); pause(1.8)
        app.swipeUp(); pause(1.0)
        app.swipeDown(); pause(0.8)

        // 5 — Back to Journal, then open the logger (the "log a set" beat).
        tab("Journal"); pause(1.2)
        let logButton = app.buttons["QuickLog.Button"]
        if logButton.waitForExistence(timeout: 3) {
            logButton.tap(); pause(3.0)
            app.swipeDown(velocity: .fast); pause(1.0)
        }
        pause(1.0)
    }
}
