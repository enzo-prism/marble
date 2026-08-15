import Foundation
import StoreKit
import UIKit

/// Decides whether Marble may ask the system for an App Store review.
///
/// Local-only: a date and a couple of counters in `UserDefaults`. Nothing
/// is sent anywhere, and there is no custom rate-us UI — the system dialog
/// is the only prompt. Call only after a real success. Never from launch.
nonisolated enum ReviewPrompt {
    nonisolated enum Event: Equatable {
        /// A workout session that was finished with at least one set.
        case finishedWorkout
        /// An imported workout that actually saved sets. Only the first one
        /// may open the dialog; later imports still count toward cooldown.
        case importedWorkout
        /// A set that beat an existing personal record (not the first-ever set).
        case personalRecord
    }

    /// 45 days between system review requests. Apple also rate-limits the
    /// dialog; this keeps Marble from asking on every success in between.
    nonisolated static let cooldown: TimeInterval = 45 * 24 * 60 * 60

    nonisolated enum Key {
        static let lastRequestAt = "reviewPrompt.lastRequestAt"
        static let successfulEventCount = "reviewPrompt.successfulEventCount"
        static let didSaveImportedWorkout = "reviewPrompt.didSaveImportedWorkout"
    }

    /// Pure gate. Tests drive this with explicit values so `.standard` stays clean.
    ///
    /// 1. UI testing never asks — a system dialog would cover every flow.
    /// 2. A later import is not the "first imported workout" success.
    /// 3. A request inside the cooldown window is skipped.
    /// 4. Otherwise this success may ask.
    nonisolated static func shouldRequest(
        after event: Event,
        lastRequestAt: Date?,
        hasSavedImportedWorkout: Bool,
        now: Date,
        isUITesting: Bool
    ) -> Bool {
        if isUITesting { return false }
        if event == .importedWorkout, hasSavedImportedWorkout { return false }
        if let lastRequestAt, now.timeIntervalSince(lastRequestAt) < cooldown {
            return false
        }
        return true
    }

    /// Same rules, read from a throwaway defaults suite.
    nonisolated static func shouldRequest(
        after event: Event,
        defaults: UserDefaults,
        now: Date,
        isUITesting: Bool
    ) -> Bool {
        shouldRequest(
            after: event,
            lastRequestAt: defaults.object(forKey: Key.lastRequestAt) as? Date,
            hasSavedImportedWorkout: defaults.bool(forKey: Key.didSaveImportedWorkout),
            now: now,
            isUITesting: isUITesting
        )
    }

    /// Records the success and, when the gate opens and a window scene is
    /// available, asks the system. Writes nothing under UI testing or XCTest
    /// so a unit/UI run cannot leak flags or present a dialog.
    @MainActor
    static func consider(
        after event: Event,
        defaults: UserDefaults = .standard,
        now: Date = AppEnvironment.now,
        isUITesting: Bool = TestHooks.isUITesting
    ) {
        guard !isUITesting, !isRunningInXCTest else { return }

        let alreadyImported = defaults.bool(forKey: Key.didSaveImportedWorkout)
        defaults.set(
            defaults.integer(forKey: Key.successfulEventCount) + 1,
            forKey: Key.successfulEventCount
        )
        if event == .importedWorkout {
            defaults.set(true, forKey: Key.didSaveImportedWorkout)
        }

        guard shouldRequest(
            after: event,
            lastRequestAt: defaults.object(forKey: Key.lastRequestAt) as? Date,
            hasSavedImportedWorkout: event == .importedWorkout ? alreadyImported : alreadyImported,
            now: now,
            isUITesting: false
        ) else { return }

        guard requestSystemReview() else { return }
        defaults.set(now, forKey: Key.lastRequestAt)
    }

    /// `AppStore.requestReview(in:)` needs a foreground scene. Siri finish
    /// and headless tests have none — returning false leaves the cooldown
    /// unstamped so a later in-app success can still ask.
    @MainActor
    @discardableResult
    static func requestSystemReview() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first else {
            return false
        }
        AppStore.requestReview(in: scene)
        return true
    }

    /// The test bundle is loaded in-process with the app host. Asking during
    /// `make unit` would present Apple's dialog over the suite.
    private static var isRunningInXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
