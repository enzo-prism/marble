import AppIntents
import Foundation

// MARK: - Dual-target intents
//
// **This file must be a member of BOTH targets:** the `marble` app (which owns the state these
// intents mutate) and the `MarbleWidgets` extension (which needs the *types* visible so it can
// build `Button(intent:)` / `ControlWidgetButton(action:)`). Same arrangement as
// `marble/Features/RestTimer/RestTimerAttributes.swift` — see MarbleWidgets/SETUP.md.
//
// The widget extension cannot see any app-only symbol (`RestActivityController`,
// `Notification.Name.marbleOpenQuickLog`, SwiftData models, `TestHooks`, …). The widget target
// defines `WIDGET_EXTENSION` in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, so **every** app-only
// reference below lives inside `#if !WIDGET_EXTENSION`, and the file's top-level imports are
// limited to `AppIntents` + `Foundation`, which both targets have.
//
// `LiveActivityIntent` is what makes the rest buttons work: unlike a plain `AppIntent` invoked
// from a widget, it is performed **in the app's process**, so it can reach the live
// `RestActivityController.shared` state machine and the running `Activity`.

/// Adds 30 seconds to the running rest timer, from the Live Activity's "+30s" button.
///
/// Repeated taps accumulate because the controller extends from the *current* end date rather
/// than from now (see `RestActivityController.extendedEnd(from:by:now:)`).
struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Extend Rest"
    static let description = IntentDescription("Adds 30 seconds to the running rest timer.")

    /// The exact ActivityKit card that rendered the button. Without this identity, a button
    /// on an old duplicate can accidentally extend a newer timer after the app relaunches.
    @Parameter(title: "Activity ID")
    var activityID: String?

    /// One tap's worth of extra rest. Kept here so the button label and the applied amount
    /// can never drift apart.
    static let extensionSeconds: TimeInterval = 30

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RestActivityController.shared.extend(by: Self.extensionSeconds, activityID: activityID)
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        #endif
        return .result()
    }
}

/// Ends the running rest timer immediately, from the Live Activity's "End" button.
struct EndRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Rest"
    static let description = IntentDescription("Ends the running rest timer and dismisses it.")

    /// Identifies the card being ended so an obsolete duplicate cannot cancel the current rest.
    @Parameter(title: "Activity ID")
    var activityID: String?

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RestActivityController.shared.cancelRest(activityID: activityID)
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        #endif
        return .result()
    }
}

/// Opens Marble straight to the set logger.
///
/// Deliberately a near-duplicate of the app-only `OpenQuickLogIntent`: a `ControlWidget` lives
/// in the extension and can only reference intent types the *extension* compiles, so the
/// Control Center / Lock Screen / Action button entry point needs its own shared type.
struct OpenQuickLogControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Set"
    static let description = IntentDescription("Opens Marble straight to the set logger.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        NotificationCenter.default.post(name: .marbleOpenQuickLog, object: nil)
        #endif
        return .result()
    }
}
