import XCTest

@MainActor
final class WorkoutDictationDeviceUITests: MarbleUITestCase {
    func testMicrophoneRecordingStopsAndReturnsEditableText() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Actual microphone acceptance requires the physical iPhone.")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_MICROPHONE_ACCEPTANCE"] == "1",
                          "Explicit device microphone check only")
        guard Self.targetBundleIdentifier == "Prism.marble.validation" else {
            return XCTFail("Microphone acceptance must use the isolated Validation app")
        }
        launchApp(fixtureMode: "empty", extraEnvironment: ["MARBLE_DRAFT_NAMESPACE": UUID().uuidString])
        let dictate = app.buttons["TextEntry.Dictate"]
        scrollToElement(dictate, in: app)
        forceTap(dictate)
        let record = app.buttons["Dictation.Record"]
        _ = waitForIdentifier("Dictation.Record", timeout: 10)

        // Consent is limited to this app's microphone prompt.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for surface in [app!, springboard] {
            let alert = surface.alerts.firstMatch
            if alert.waitForExistence(timeout: 2),
               alert.label.localizedCaseInsensitiveContains("microphone"),
               alert.label.contains("Marble Validation") {
                // iOS 27.2 exposes the native Allow button twice as nested
                // nodes. Keep the exact microphone-service scope and use its
                // first match instead of an ambiguous visible-label query.
                let allow = alert.buttons.matching(identifier: "kTCCServiceMicrophone-allow-button").firstMatch
                if allow.exists { allow.tap() }
            }
        }
        if record.exists, record.isEnabled, record.label == "Record" { record.tap() }
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Stop Recording"), object: record)
        guard await XCTWaiter.fulfillment(of: [recording], timeout: 120) == .completed else {
            if app.buttons["Dictation.Cancel"].exists { app.buttons["Dictation.Cancel"].tap() }
            return XCTFail("Recording did not start after microphone consent and local asset preparation")
        }

        // The Mac-side harness plays the bundled 4.3-second synthetic workout
        // on this marker. No transcript is printed or attached to the result.
        NSLog("MARBLE_MICROPHONE_READY")
        try await Task.sleep(for: .seconds(12))
        forceTap(record)
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Record"), object: record)
        guard await XCTWaiter.fulfillment(of: [stopped], timeout: 60) == .completed else {
            if app.buttons["Dictation.Cancel"].exists { app.buttons["Dictation.Cancel"].tap() }
            return XCTFail("Stop must finish the recording and release the microphone")
        }
        let text = app.staticTexts["Dictation.Transcript"].label.lowercased()
        guard text.contains("bench"), text.contains("press"), text.contains("pound") else {
            app.buttons["Dictation.Cancel"].tap()
            return XCTFail("The synthetic workout was not captured through the microphone")
        }
        forceTap(app.buttons["Dictation.UseText"])
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 10)
        XCTAssertTrue((editor.value as? String)?.lowercased().contains("bench") == true)
        let clear = app.buttons["TextEntry.Clear"]
        scrollToElement(clear, in: app)
        forceTap(clear)
        #endif
    }
}
