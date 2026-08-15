import XCTest
@testable import marble

/// The review prompt has two failure modes that are both expensive, so the
/// gate is pinned here:
///
/// - Asking on launch, during UI testing, or on a cold import-less session
///   would put Apple's dialog over flows that are not a real success.
/// - Asking again inside the cooldown would nag; never asking after a
///   genuine finish/import/PR would leave the Store at zero ratings.
@MainActor
final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - Real successes may ask

    func testFinishedWorkoutMayRequestWhenNeverAsked() {
        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                lastRequestAt: nil,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: false
            )
        )
    }

    func testFirstImportedWorkoutMayRequest() {
        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .importedWorkout,
                lastRequestAt: nil,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: false
            )
        )
    }

    func testPersonalRecordMayRequest() {
        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .personalRecord,
                lastRequestAt: nil,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: false
            )
        )
    }

    // MARK: - First-import only

    func testLaterImportedWorkoutDoesNotRequest() {
        XCTAssertFalse(
            ReviewPrompt.shouldRequest(
                after: .importedWorkout,
                lastRequestAt: nil,
                hasSavedImportedWorkout: true,
                now: now,
                isUITesting: false
            )
        )
    }

    func testAlreadyHavingImportedDoesNotBlockAFinishedWorkout() {
        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                lastRequestAt: nil,
                hasSavedImportedWorkout: true,
                now: now,
                isUITesting: false
            )
        )
    }

    // MARK: - Cooldown

    func testRequestInsideCooldownIsSkipped() {
        let last = now.addingTimeInterval(-14 * 24 * 60 * 60)
        XCTAssertFalse(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                lastRequestAt: last,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: false
            )
        )
    }

    func testRequestAfterCooldownMayAskAgain() {
        let last = now.addingTimeInterval(-ReviewPrompt.cooldown)
        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .personalRecord,
                lastRequestAt: last,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: false
            )
        )
    }

    func testCooldownIsFortyFiveDays() {
        XCTAssertEqual(ReviewPrompt.cooldown, 45 * 24 * 60 * 60)
    }

    // MARK: - UI testing

    func testUITestingNeverRequests() {
        XCTAssertFalse(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                lastRequestAt: nil,
                hasSavedImportedWorkout: false,
                now: now,
                isUITesting: true
            )
        )
    }

    // MARK: - Defaults wiring

    func testDefaultsSuiteReadsThePersistedDate() throws {
        let suiteName = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                defaults: defaults,
                now: now,
                isUITesting: false
            )
        )

        defaults.set(now, forKey: ReviewPrompt.Key.lastRequestAt)
        XCTAssertFalse(
            ReviewPrompt.shouldRequest(
                after: .finishedWorkout,
                defaults: defaults,
                now: now.addingTimeInterval(60),
                isUITesting: false
            )
        )
    }

    func testKeysAreStable() {
        XCTAssertEqual(ReviewPrompt.Key.lastRequestAt, "reviewPrompt.lastRequestAt")
        XCTAssertEqual(ReviewPrompt.Key.successfulEventCount, "reviewPrompt.successfulEventCount")
        XCTAssertEqual(ReviewPrompt.Key.didSaveImportedWorkout, "reviewPrompt.didSaveImportedWorkout")
    }
}
