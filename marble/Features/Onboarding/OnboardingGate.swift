import Foundation

/// Decides whether the first-run onboarding flow should appear.
///
/// Kept deliberately pure (no SwiftUI, no ambient state) because the wrong
/// answer here is expensive in two directions:
///
/// 1. **UI tests.** Every UI test launches against a fresh in-memory store, so
///    a naive "no completion flag ⇒ show onboarding" rule would drop a modal
///    over all 36 of them.
/// 2. **Existing users.** Someone upgrading from 2.1 already has a journal.
///    The legacy `didSeedMarbleData` flag is the only reliable marker that the
///    app has run before (it predates `didCompleteOnboarding`), so its presence
///    means "not a new user" — such a person must never be onboarded, and the
///    caller stamps completion so the question is never asked again.
///
/// Two things make that seed flag treacherous, and both are handled here:
///
/// - **It is written by the current launch.** `SeedData` sets it during first-run
///   seeding, so reading it live answers "has seeding run yet *this* launch",
///   not "did this app run before". `MarbleApp.init()` therefore captures it
///   once, before any seeding can start, and the gate reads only that capture.
/// - **It cannot distinguish an interrupted first run from an upgrade.** After a
///   fresh install seeds and the user force-quits on page 2 of onboarding, the
///   next launch sees exactly what a 2.1 upgrader looks like. `didBeginOnboarding`
///   is the extra bit that separates them, so an interrupted flow resumes instead
///   of being suppressed forever.
enum OnboardingGate {
    /// Written by `SeedData` on the first real (non-UI-test) launch. Lives in
    /// `UserDefaults.standard` and is read directly, never through
    /// `SharedDefaults` — it is not one of the migrated keys.
    nonisolated static let legacySeedDefaultsKey = "didSeedMarbleData"

    /// The full answer: whether to present, whether to silently record
    /// completion for an existing user who is being skipped, and whether to
    /// remember that the flow has now been started.
    nonisolated struct Decision: Equatable {
        /// Show `OnboardingView`.
        var presentsOnboarding: Bool
        /// Write `didCompleteOnboarding = true` without showing anything, so an
        /// upgrading user is never asked again.
        var marksCompleteSilently: Bool
        /// Write `didBeginOnboarding = true`, so quitting midway resumes the
        /// flow next launch rather than losing it.
        var recordsOnboardingStarted: Bool

        nonisolated init(
            presentsOnboarding: Bool,
            marksCompleteSilently: Bool,
            recordsOnboardingStarted: Bool = false
        ) {
            self.presentsOnboarding = presentsOnboarding
            self.marksCompleteSilently = marksCompleteSilently
            self.recordsOnboardingStarted = recordsOnboardingStarted
        }
    }

    /// Rules, in priority order:
    /// 1. `forceOnboarding` (the `MARBLE_FORCE_ONBOARDING` test hook) always wins.
    /// 2. UI testing never shows it.
    /// 3. Already completed never shows it.
    /// 4. Already *started* but not completed always shows it — the user quit
    ///    midway and still owes us a weekly target and a weight unit.
    /// 5. Data seeded on an *earlier* launch means an existing user — never show it.
    /// 6. Otherwise this is a genuine first run.
    ///
    /// `hasSeededData` must be the value captured at launch (see
    /// `hadSeededDataAtLaunch`), never a live read.
    nonisolated static func shouldPresent(
        hasCompletedOnboarding: Bool,
        hasSeededData: Bool,
        hasBegunOnboarding: Bool = false,
        isUITesting: Bool,
        forceOnboarding: Bool
    ) -> Bool {
        if forceOnboarding { return true }
        if isUITesting { return false }
        if hasCompletedOnboarding { return false }
        if hasBegunOnboarding { return true }
        if hasSeededData { return false }
        return true
    }

    nonisolated static func decide(
        hasCompletedOnboarding: Bool,
        hasSeededData: Bool,
        hasBegunOnboarding: Bool = false,
        isUITesting: Bool,
        forceOnboarding: Bool
    ) -> Decision {
        let presents = shouldPresent(
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasSeededData: hasSeededData,
            hasBegunOnboarding: hasBegunOnboarding,
            isUITesting: isUITesting,
            forceOnboarding: forceOnboarding
        )

        // Only the "existing user upgrading" branch needs a silent stamp. UI
        // testing must not write anything (the flag would leak across runs on a
        // device-backed suite), and a forced run is finished by the flow itself.
        let marksComplete = !presents
            && !forceOnboarding
            && !isUITesting
            && !hasCompletedOnboarding
            && hasSeededData

        // Same "write nothing under test" rule: a forced run is a hook, not a
        // real first run, and must not leave a flag that makes onboarding
        // sticky on the next launch.
        let recordsStarted = presents
            && !forceOnboarding
            && !isUITesting
            && !hasBegunOnboarding

        return Decision(
            presentsOnboarding: presents,
            marksCompleteSilently: marksComplete,
            recordsOnboardingStarted: recordsStarted
        )
    }

    // MARK: - Launch capture

    /// `didSeedMarbleData` as it stood *before* this launch could seed.
    ///
    /// `MarbleApp.init()` fills this in. Nil means capture never happened
    /// (SwiftUI previews, a unit test driving the live path), in which case a
    /// live read is the safer fallback: it can misclassify a genuine first run,
    /// but it never re-onboards someone who already has a journal.
    private static var capturedSeededDataAtLaunch: Bool?

    static var hadSeededDataAtLaunch: Bool {
        capturedSeededDataAtLaunch ?? UserDefaults.standard.bool(forKey: legacySeedDefaultsKey)
    }

    /// Call once, at the very top of `MarbleApp.init()`, before the model
    /// container exists and therefore before any seeding can run. Reading the
    /// flag later races `SeedData` — `marbleApp` seeds inside the
    /// `WindowGroup`'s `.task` while `ContentView` evaluates the gate in its
    /// own, and SwiftUI does not order the two.
    static func captureLaunchState(legacy: UserDefaults = .standard) {
        capturedSeededDataAtLaunch = legacy.bool(forKey: legacySeedDefaultsKey)
    }

    /// Test seam: forget the capture so the next `captureLaunchState` (or the
    /// live fallback) is what answers.
    static func resetLaunchCaptureForTesting() {
        capturedSeededDataAtLaunch = nil
    }

    // MARK: - Live evaluation

    /// Live evaluation against the real defaults. Both persisted flags come
    /// from `SharedDefaults`; the seed flag comes from the launch capture
    /// rather than from a store this launch mutates.
    static func currentDecision(
        shared: UserDefaults = SharedDefaults.suite,
        hadSeededDataAtLaunch: Bool? = nil
    ) -> Decision {
        decide(
            hasCompletedOnboarding: shared.bool(forKey: SharedDefaults.Key.didCompleteOnboarding),
            hasSeededData: hadSeededDataAtLaunch ?? Self.hadSeededDataAtLaunch,
            hasBegunOnboarding: shared.bool(forKey: SharedDefaults.Key.didBeginOnboarding),
            isUITesting: TestHooks.isUITesting,
            forceOnboarding: TestHooks.forceOnboarding
        )
    }

    /// Records that the flow has been shown at least once.
    static func markBegun(in shared: UserDefaults = SharedDefaults.suite) {
        shared.set(true, forKey: SharedDefaults.Key.didBeginOnboarding)
    }

    /// Records completion. Used both when the user finishes the flow and when
    /// an existing user is silently skipped.
    static func markComplete(in shared: UserDefaults = SharedDefaults.suite) {
        shared.set(true, forKey: SharedDefaults.Key.didCompleteOnboarding)
    }
}
