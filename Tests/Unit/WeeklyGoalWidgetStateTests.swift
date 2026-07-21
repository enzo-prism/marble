import XCTest
@testable import marble

/// Pins the app/widget wire format: round-tripping, the staleness cliff, and
/// the clamped progress fraction the ring renders.
///
/// The snapshot now travels through `SharedKeychain`, so these cases exercise
/// the **pure** `encoded()`/`decoded(from:)` pair rather than a store. Nothing
/// here touches the real keychain (nor `UserDefaults`) — see
/// `SharedKeychainQueryTests` for why.
///
/// `@MainActor` because `WeeklyGoalWidgetPublisher` is main-actor isolated.
@MainActor
final class WeeklyGoalWidgetStateTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_736_899_200) // 2025-01-15 00:00 UTC

    private func state(
        target: Int = 3,
        sessions: Int = 2,
        streak: Int = 4,
        flex: Int = 1,
        stateRaw: String = "inProgress",
        generatedAt: Date? = nil
    ) -> WeeklyGoalWidgetState {
        WeeklyGoalWidgetState(
            target: target,
            thisWeekSessions: sessions,
            streakWeeks: streak,
            flexTokens: flex,
            stateRaw: stateRaw,
            weekStart: reference,
            generatedAt: generatedAt ?? reference
        )
    }

    // MARK: Wire format

    func testEncodeDecodeRoundTrip() {
        let original = state()

        let decoded = WeeklyGoalWidgetState.decoded(from: original.encoded())

        XCTAssertEqual(decoded, original)
    }

    func testEncodePreservesEveryField() {
        let original = state(target: 5, sessions: 4, streak: 11, flex: 2, stateRaw: "atRisk")

        let decoded = WeeklyGoalWidgetState.decoded(from: original.encoded())

        XCTAssertEqual(decoded?.target, 5)
        XCTAssertEqual(decoded?.thisWeekSessions, 4)
        XCTAssertEqual(decoded?.streakWeeks, 11)
        XCTAssertEqual(decoded?.flexTokens, 2)
        XCTAssertEqual(decoded?.stateRaw, "atRisk")
        XCTAssertEqual(decoded?.weekStart, reference)
        XCTAssertEqual(decoded?.generatedAt, reference)
    }

    func testDecodeReturnsNilWhenNothingPublished() {
        // What an unreadable keychain hands back: no bytes at all.
        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: nil))
    }

    func testDecodeReturnsNilOnEmptyPayload() {
        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: Data()))
    }

    func testDecodeReturnsNilOnCorruptPayload() {
        // Garbage must degrade to the neutral card, never trap.
        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: Data("not json".utf8)))
        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: Data([0x00, 0xFF, 0x10, 0x83])))
    }

    func testDecodeReturnsNilOnWellFormedJSONOfTheWrongShape() {
        let foreign = Data(#"{"target":3,"unrelated":true}"#.utf8)

        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: foreign))
    }

    func testDecodeReturnsNilOnTruncatedPayload() throws {
        let full = try XCTUnwrap(state().encoded())
        let truncated = Data(full.prefix(full.count / 2))

        XCTAssertNil(WeeklyGoalWidgetState.decoded(from: truncated))
    }

    func testEncodingIsDeterministicForEqualStates() {
        // Two publishes of the same week must produce the same bytes, so the
        // upsert can't be fooled into churning the keychain item.
        XCTAssertEqual(state(sessions: 2).encoded(), state(sessions: 2).encoded())
        XCTAssertNotEqual(state(sessions: 1).encoded(), state(sessions: 3).encoded())
    }

    // MARK: Staleness

    func testFreshSnapshotIsNotStale() {
        let snapshot = state(generatedAt: reference)

        XCTAssertFalse(snapshot.isStale(now: reference))
        XCTAssertFalse(snapshot.isStale(now: reference.addingTimeInterval(60 * 60 * 24)))
    }

    func testStalenessBoundaryIsExactlyEightDays() {
        let snapshot = state(generatedAt: reference)
        let eightDays = reference.addingTimeInterval(8 * 24 * 60 * 60)

        // Exactly at the boundary is still trusted; one second past is not.
        XCTAssertFalse(snapshot.isStale(now: eightDays))
        XCTAssertTrue(snapshot.isStale(now: eightDays.addingTimeInterval(1)))
    }

    func testSnapshotFromTheFutureIsNotStale() {
        // Clock skew must not blank the widget.
        let snapshot = state(generatedAt: reference.addingTimeInterval(60 * 60))

        XCTAssertFalse(snapshot.isStale(now: reference))
    }

    // MARK: Progress

    func testProgressFractionIsSessionsOverTarget() {
        XCTAssertEqual(state(target: 4, sessions: 1).progressFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state(target: 3, sessions: 0).progressFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(state(target: 3, sessions: 3).progressFraction, 1, accuracy: 0.0001)
    }

    func testProgressFractionClampsAboveTarget() {
        XCTAssertEqual(state(target: 3, sessions: 9).progressFraction, 1, accuracy: 0.0001)
    }

    func testProgressFractionIsZeroForNonPositiveTarget() {
        XCTAssertEqual(state(target: 0, sessions: 2).progressFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(state(target: -3, sessions: 2).progressFraction, 0, accuracy: 0.0001)
    }

    func testProgressFractionClampsNegativeSessions() {
        XCTAssertEqual(state(target: 3, sessions: -1).progressFraction, 0, accuracy: 0.0001)
    }

    // MARK: Placeholder

    func testPlaceholderIsRenderableAndNotStale() {
        let placeholder = WeeklyGoalWidgetState.placeholder

        XCTAssertGreaterThan(placeholder.target, 0)
        XCTAssertGreaterThanOrEqual(placeholder.thisWeekSessions, 0)
        XCTAssertLessThanOrEqual(placeholder.thisWeekSessions, placeholder.target)
        XCTAssertGreaterThan(placeholder.progressFraction, 0)
        XCTAssertLessThanOrEqual(placeholder.progressFraction, 1)
        // Gallery previews must not fall through to the neutral empty card.
        XCTAssertFalse(placeholder.isStale(now: Date()))
    }

    func testPlaceholderStateRawIsOneOfTheEngineStates() {
        let known = ["fresh", "hit", "inProgress", "atRisk", "comeback"]

        XCTAssertTrue(known.contains(WeeklyGoalWidgetState.placeholder.stateRaw))
    }

    // MARK: Engine mapping

    func testPublisherMapsEveryGoalState() {
        XCTAssertEqual(WeeklyGoalWidgetPublisher.raw(.fresh), "fresh")
        XCTAssertEqual(WeeklyGoalWidgetPublisher.raw(.hit), "hit")
        XCTAssertEqual(WeeklyGoalWidgetPublisher.raw(.inProgress), "inProgress")
        XCTAssertEqual(WeeklyGoalWidgetPublisher.raw(.atRisk), "atRisk")
        XCTAssertEqual(WeeklyGoalWidgetPublisher.raw(.comeback), "comeback")
    }
}
