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
    /// Native API lifecycle in the isolated Validation store. Simulator results
    /// do not establish physical sensors or extended background runtime.
    func testNativeHealthWorkoutStartPauseResumeSaveAndCleanup() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_NATIVE_HEALTH_ACCEPTANCE"] == "1", "Explicit native Health acceptance only")
        XCTAssertEqual(Self.targetBundleIdentifier, "Prism.marble.validation")
        launchApp(fixtureMode: "empty", extraEnvironment: ["MARBLE_DEVICE_ACCEPTANCE": "1"])
        let definitions = IntentDefinitions(bundleIdentifier: Self.targetBundleIdentifier)
        _ = try await definitions.intents["PrepareWorkoutIntentTests"].makeIntent().run()
        _ = try await step("prepare")
        // Request consent from the foreground Settings UI, rather than holding
        // an App Intents RPC open while the system presents its privacy sheet.
        let existingPermission = try await step("status")
        if existingPermission["authorized"] as? Bool != true {
            openAddToolbarAction("Workout.Settings")
            let toggle = app.switches["Settings.LiveHealthWorkout"]
            scrollToElement(toggle, in: app)
            // The SwiftUI switch's AX frame includes its multi-line label. Tap
            // the trailing thumb rather than the middle of the label text.
            tapVisible(toggle, normalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            try await Task.sleep(for: .seconds(1))
            for _ in 0..<24 {
                let surfaces = [app!, XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService"), XCUIApplication(bundleIdentifier: "com.apple.springboard")]
                var allowed = false
                for surface in surfaces {
                    // iOS 27's granular consent sheet has no Select All button.
                    // Enable the exact workout-writing scope rather than tapping
                    // a disabled Allow button with every permission still off.
                    let writeWorkouts = surface.switches["UIA.Health.Write.Workouts.SwitchCell.Switch"]
                    if writeWorkouts.exists, writeWorkouts.isHittable,
                       writeWorkouts.value as? String == "0" { writeWorkouts.tap() }
                    for label in ["Allow", "Share", "Continue"] {
                        let button = surface.buttons[label].firstMatch
                        if button.exists, button.isHittable, button.isEnabled {
                            let hierarchy = XCTAttachment(string: surface.debugDescription)
                            hierarchy.name = "Health authorization controls"
                            hierarchy.lifetime = .keepAlways
                            add(hierarchy)
                            let screenshot = XCTAttachment(screenshot: surface.screenshot())
                            screenshot.name = "Health authorization selection"
                            screenshot.lifetime = .keepAlways
                            add(screenshot)
                            button.tap(); allowed = true; break
                        }
                    }
                    if allowed { break }
                }
                if allowed { break }
                app.swipeUp()
                try await Task.sleep(for: .milliseconds(500))
            }
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
            XCUIDevice.shared.press(.home)
            try await Task.sleep(for: .seconds(2))
            app.activate()
            let returned = try await step("status")
            XCTAssertEqual(returned["running"] as? Bool, true)
            let finished = try await step("finish")
            XCTAssertEqual(finished["running"] as? Bool, false)
            XCTAssertEqual(finished["saved"] as? Bool, true, String(describing: finished))
            _ = try await step("cleanup")
        } catch {
            _ = try? await step("cleanup")
            throw error
        }
    }
}
#endif
