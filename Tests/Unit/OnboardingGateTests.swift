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

    // MARK: - Quitting midway through onboarding

    /// **The regression.** A fresh install seeds (setting `didSeedMarbleData`),
    /// shows onboarding, and the user force-quits on page 2. On the next launch
    /// that store is byte-for-byte indistinguishable from a 2.1 upgrader's, so
    /// the seed flag alone would skip the flow permanently — leaving the user
    /// with no weekly target and no weight unit, and no way back.
    func testInterruptedOnboardingResumesOnTheNextLaunch() {
        XCTAssertTrue(
            OnboardingGate.shouldPresent(
                hasCompletedOnboarding: false,
                hasSeededData: true,
                hasBegunOnboarding: true,
                isUITesting: false,
                forceOnboarding: false
            )
        )
    }

    /// ...and it must not be stamped complete on the way past.
    func testInterruptedOnboardingIsNotSilentlyMarkedComplete() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: true,
            hasBegunOnboarding: true,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertTrue(decision.presentsOnboarding)
        XCTAssertFalse(decision.marksCompleteSilently)
        // Already recorded — no need to rewrite it every launch.
        XCTAssertFalse(decision.recordsOnboardingStarted)
    }

    /// The first presentation is what records the marker.
    func testFirstRunRecordsThatOnboardingStarted() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: false,
            hasBegunOnboarding: false,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertTrue(decision.presentsOnboarding)
        XCTAssertTrue(decision.recordsOnboardingStarted)
    }

    /// Finishing wins over having started — a completed user is never asked again.
    func testCompletionOutranksTheStartedMarker() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: true,
            hasSeededData: true,
            hasBegunOnboarding: true,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertFalse(decision.presentsOnboarding)
        XCTAssertFalse(decision.marksCompleteSilently)
        XCTAssertFalse(decision.recordsOnboardingStarted)
    }

    /// Neither UI testing nor the force hook may leave the marker behind; a
    /// device-backed suite would carry it into every later run.
    func testTestHooksNeverRecordThatOnboardingStarted() {
        for forceOnboarding in [true, false] {
            let underUITest = OnboardingGate.decide(
                hasCompletedOnboarding: false,
                hasSeededData: false,
                hasBegunOnboarding: false,
                isUITesting: true,
                forceOnboarding: forceOnboarding
            )
            XCTAssertFalse(underUITest.recordsOnboardingStarted)
        }

        let forcedOutsideUITesting = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: false,
            hasBegunOnboarding: false,
            isUITesting: false,
            forceOnboarding: true
        )
        XCTAssertTrue(forcedOutsideUITesting.presentsOnboarding)
        XCTAssertFalse(forcedOutsideUITesting.recordsOnboardingStarted)
    }

    /// An upgrader from 2.1 has never started the flow, so nothing changes for
    /// them: still skipped, still stamped.
    func testUpgraderWithoutTheStartedMarkerIsStillSkippedAndStamped() {
        let decision = OnboardingGate.decide(
            hasCompletedOnboarding: false,
            hasSeededData: true,
            hasBegunOnboarding: false,
            isUITesting: false,
            forceOnboarding: false
        )
        XCTAssertFalse(decision.presentsOnboarding)
        XCTAssertTrue(decision.marksCompleteSilently)
    }

    // MARK: - Launch capture

    /// The latent ordering hazard: if seeding wins the race against
    /// `ContentView`'s task, a live read reports `true` on a genuine first run
    /// and onboarding never appears on any install. The capture is taken in
    /// `MarbleApp.init()` before seeding can start, so a later write to the
    /// same store cannot change the answer.
    @MainActor
    func testLaunchCaptureIgnoresASeedFlagWrittenAfterCapture() throws {
        let suiteName = "OnboardingGateTests.capture.\(UUID().uuidString)"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            OnboardingGate.resetLaunchCaptureForTesting()
            legacy.removePersistentDomain(forName: suiteName)
        }

        // Fresh install: nothing seeded yet when the app initialises.
        OnboardingGate.captureLaunchState(legacy: legacy)
        // Seeding then runs and stamps the flag, as it does on every install.
        legacy.set(true, forKey: OnboardingGate.legacySeedDefaultsKey)

        XCTAssertFalse(
            OnboardingGate.hadSeededDataAtLaunch,
            "the gate must not see this launch's own seeding"
        )
    }

    /// An upgrader's flag is already set when the capture is taken.
    @MainActor
    func testLaunchCaptureSeesAFlagWrittenByAnEarlierLaunch() throws {
        let suiteName = "OnboardingGateTests.capture.\(UUID().uuidString)"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            OnboardingGate.resetLaunchCaptureForTesting()
            legacy.removePersistentDomain(forName: suiteName)
        }

        legacy.set(true, forKey: OnboardingGate.legacySeedDefaultsKey)
        OnboardingGate.captureLaunchState(legacy: legacy)

        XCTAssertTrue(OnboardingGate.hadSeededDataAtLaunch)
    }

    // MARK: - Key wiring

    /// The legacy key is the load-bearing signal for "this app has run before";
    /// it must keep matching what `SeedData` writes.
    func testLegacySeedKeyMatchesSeedDataKey() {
        XCTAssertEqual(OnboardingGate.legacySeedDefaultsKey, "didSeedMarbleData")
    }

    /// The started marker is persisted, so renaming its key would silently
    /// re-arm the "onboarding suppressed forever" bug for anyone mid-flow.
    func testBegunOnboardingKeyIsStable() {
        XCTAssertEqual(SharedDefaults.Key.didBeginOnboarding, "didBeginOnboarding")
    }
}
