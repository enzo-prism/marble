import XCTest
@testable import marble

/// The onboarding gate has two failure modes that are both expensive, so every
/// branch is pinned here:
///
/// - Showing onboarding during UI testing drops a modal over all 36 UI tests.
/// - Showing it to someone upgrading from 2.1 asks an existing user to
///   re-introduce themselves to an app full of their own data.
final class OnboardingGateTests: XCTestCase {
    // MARK: - The happy path

    func testFreshInstallPresentsOnboarding() {
        XCTAssertTrue(
            OnboardingGate.shouldPresent(
                hasCompletedOnboarding: false,
                hasSeededData: false,
                isUITesting: false,
                forceOnboarding: false
            )
        )
    }

    func testFreshInstallDoesNotSilentlyMarkComplete() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: false,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertTrue(decision.presentsOnboarding)
        XCTAssertFalse(decision.marksCompleteSilently)
    }

    // MARK: - Existing users upgrading to 2.2

    func testSeededExistingUserIsNeverOnboarded() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                hasCompletedOnboarding: false,
                hasSeededData: true,
                isUITesting: false,
                forceOnboarding: false
            )
        )
    }

    /// The important half: skipping isn't enough, the flag has to be written or
    /// the same user gets asked again on the next launch.
    func testSeededExistingUserIsMarkedCompleteSilently() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: true,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertFalse(decision.presentsOnboarding)
        XCTAssertTrue(decision.marksCompleteSilently)
    }

    // MARK: - Already completed

    func testCompletedOnboardingDoesNotRepeat() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                hasCompletedOnboarding: true,
                hasSeededData: false,
                isUITesting: false,
                forceOnboarding: false
            )
        )
    }

    func testCompletedOnboardingDoesNotRewriteTheFlag() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: true,
            hasSeededData: true,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertFalse(decision.presentsOnboarding)
        XCTAssertFalse(decision.marksCompleteSilently)
    }

    // MARK: - UI testing

    /// Every UI test launches with a fresh in-memory store, which looks exactly
    /// like a first install. Without this branch onboarding would cover them all.
    func testUITestingNeverPresentsOnboardingOnAFreshStore() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                hasCompletedOnboarding: false,
                hasSeededData: false,
                isUITesting: true,
                forceOnboarding: false
            )
        )
    }

    /// UI tests must not leave persisted state behind either.
    func testUITestingNeverWritesTheCompletionFlag() {
        for hasSeededData in [true, false] {
            let decision = OnboardingGate.decide(
                hasCompletedOnboarding: false,
                hasSeededData: hasSeededData,
                isUITesting: true,
                forceOnboarding: false
            )
            XCTAssertFalse(decision.presentsOnboarding)
            XCTAssertFalse(decision.marksCompleteSilently)
        }
    }

    // MARK: - The force hook

    func testForceOnboardingOverridesEverything() {
        for hasCompleted in [true, false] {
            for hasSeeded in [true, false] {
                for isUITesting in [true, false] {
                    XCTAssertTrue(
                        OnboardingGate.shouldPresent(
                            hasCompletedOnboarding: hasCompleted,
                            hasSeededData: hasSeeded,
                            isUITesting: isUITesting,
                            forceOnboarding: true
                        ),
                        "force should win for completed=\(hasCompleted) seeded=\(hasSeeded) uiTesting=\(isUITesting)"
                    )
                }
            }
        }
    }

    /// A forced run finishes through the flow itself, so the gate must not
    /// pre-emptively stamp completion.
    func testForcedOnboardingDoesNotSilentlyMarkComplete() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: true,
            isUITesting: true,
            forceOnboarding: true
        )
        XCTAssertTrue(decision.presentsOnboarding)
        XCTAssertFalse(decision.marksCompleteSilently)
    }

    // MARK: - Key wiring

    /// The legacy key is the load-bearing signal for "this app has run before";
    /// it must keep matching what `SeedData` writes.
    func testLegacySeedKeyMatchesSeedDataKey() {
        XCTAssertEqual(OnboardingGate.legacySeedDefaultsKey, "didSeedMarbleData")
    }
}
