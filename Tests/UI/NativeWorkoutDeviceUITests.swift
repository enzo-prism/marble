#if canImport(AppIntentsTesting)
import AppIntentsTesting
import XCTest

@available(iOS 27.0, *)
@MainActor
final class NativeWorkoutDeviceUITests: MarbleUITestCase {
    private func step(_ action: String) async throws -> [String: Any] {
        let definitions = IntentDefinitions(bundleIdentifier: Self.targetBundleIdentifier)
        let result = try await definitions.intents["HealthDeviceAcceptanceIntent"].makeIntent(action: action).run()
        let text: String = try result.value
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func testRealHealthWorkoutStartPauseResumeSaveAndCleanup() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Native Health acceptance requires the connected physical iPhone.")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_NATIVE_HEALTH_ACCEPTANCE"] == "1", "Explicit device acceptance only")
        XCTAssertEqual(Self.targetBundleIdentifier, "Prism.marble.validation")
        launchApp(fixtureMode: "empty", extraEnvironment: ["MARBLE_DEVICE_ACCEPTANCE": "1"])
        let definitions = IntentDefinitions(bundleIdentifier: Self.targetBundleIdentifier)
        _ = try await definitions.intents["PrepareWorkoutIntentTests"].makeIntent().run()
        _ = try await step("prepare")
        // Request consent from the foreground Settings UI, rather than holding
        // an App Intents RPC open while the system presents its privacy sheet.
        openAddToolbarAction("Workout.Settings")
        let toggle = app.switches["Settings.LiveHealthWorkout"]
        scrollToElement(toggle, in: app)
        forceTap(toggle)
        try await Task.sleep(for: .seconds(1))
        for _ in 0..<24 {
            let surfaces = [app!, XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService"), XCUIApplication(bundleIdentifier: "com.apple.springboard")]
            var allowed = false
            for surface in surfaces {
                let selectAll = surface.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select All' OR label == 'Turn On All'")).firstMatch
                if selectAll.exists, selectAll.isHittable { selectAll.tap() }
                for label in ["Allow", "Share", "Continue"] {
                    let button = surface.buttons[label].firstMatch
                    if button.exists, button.isHittable { button.tap(); allowed = true; break }
                }
                if allowed { break }
            }
            if allowed { break }
            app.swipeUp()
            try await Task.sleep(for: .milliseconds(500))
        }
        let permission = try await step("status")
        if permission["authorized"] as? Bool != true {
            _ = try? await step("cleanup")
            throw XCTSkip("Health workout writing was not authorized")
        }
        do {
            let started = try await step("start")
            XCTAssertEqual(started["running"] as? Bool, true, String(describing: started))
            try await Task.sleep(for: .seconds(2))
            let paused = try await step("pause")
            XCTAssertEqual(paused["paused"] as? Bool, true)
            let resumed = try await step("resume")
            XCTAssertEqual(resumed["paused"] as? Bool, false)
            let finished = try await step("finish")
            XCTAssertEqual(finished["running"] as? Bool, false)
            XCTAssertEqual(finished["saved"] as? Bool, true, String(describing: finished))
            _ = try await step("cleanup")
        } catch {
            _ = try? await step("cleanup")
            throw error
        }
        #endif
    }
}
#endif
