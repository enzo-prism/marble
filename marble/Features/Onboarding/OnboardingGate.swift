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
enum OnboardingGate {
    /// Written by `SeedData` on the first real (non-UI-test) launch. Lives in
    /// `UserDefaults.standard`, not the App Group suite — it was never migrated.
    nonisolated static let legacySeedDefaultsKey = "didSeedMarbleData"

    /// The full answer: whether to present, and whether to silently record
    /// completion for an existing user who is being skipped.
    nonisolated struct Decision: Equatable {
        /// Show `OnboardingView`.
        var presentsOnboarding: Bool
        /// Write `didCompleteOnboarding = true` without showing anything, so an
        /// upgrading user is never asked again.
        var marksCompleteSilently: Bool

        nonisolated init(presentsOnboarding: Bool, marksCompleteSilently: Bool) {
            self.presentsOnboarding = presentsOnboarding
            self.marksCompleteSilently = marksCompleteSilently
        }
    }

    /// Rules, in priority order:
    /// 1. `forceOnboarding` (the `MARBLE_FORCE_ONBOARDING` test hook) always wins.
    /// 2. UI testing never shows it.
    /// 3. Already completed never shows it.
    /// 4. Already-seeded data means an existing user — never show it.
    /// 5. Otherwise this is a genuine first run.
    nonisolated static func shouldPresent(
        hasCompletedOnboarding: Bool,
        hasSeededData: Bool,
        isUITesting: Bool,
        forceOnboarding: Bool
    ) -> Bool {
        if forceOnboarding { return true }
        if isUITesting { return false }
        if hasCompletedOnboarding { return false }
        if hasSeededData { return false }
        return true
    }

    nonisolated static func decide(
        hasCompletedOnboarding: Bool,
        hasSeededData: Bool,
        isUITesting: Bool,
        forceOnboarding: Bool
    ) -> Decision {
        let presents = shouldPresent(
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasSeededData: hasSeededData,
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

        return Decision(presentsOnboarding: presents, marksCompleteSilently: marksComplete)
    }

    /// Live evaluation against the real defaults. `didCompleteOnboarding` lives
    /// in the shared App Group suite; the legacy seed flag does not.
    static func currentDecision(
        shared: UserDefaults = SharedDefaults.suite,
        legacy: UserDefaults = .standard
    ) -> Decision {
        decide(
            hasCompletedOnboarding: shared.bool(forKey: SharedDefaults.Key.didCompleteOnboarding),
            hasSeededData: legacy.bool(forKey: legacySeedDefaultsKey),
            isUITesting: TestHooks.isUITesting,
            forceOnboarding: TestHooks.forceOnboarding
        )
    }

    /// Records completion. Used both when the user finishes the flow and when
    /// an existing user is silently skipped.
    static func markComplete(in shared: UserDefaults = SharedDefaults.suite) {
        shared.set(true, forKey: SharedDefaults.Key.didCompleteOnboarding)
    }
}
