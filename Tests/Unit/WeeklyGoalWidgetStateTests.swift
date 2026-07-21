import XCTest
@testable import marble

/// Pins the app/widget wire format: round-tripping, the staleness cliff, and
/// the clamped progress fraction the ring renders.
///
/// `@MainActor` because `WeeklyGoalWidgetPublisher` is main-actor isolated.
@MainActor
final class WeeklyGoalWidgetStateTests: XCTestCase {
    private var suiteName = ""
    private var suite: UserDefaults!

    private let reference = Date(timeIntervalSince1970: 1_736_899_200) // 2025-01-15 00:00 UTC

    override func setUp() {
        super.setUp()
        suiteName = "marble.tests.widgetstate.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(suite)
    }

    override func tearDown() {
        suite?.removePersistentDomain(forName: suiteName)
        suite = nil
        super.tearDown()
    }

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

    // MARK: Persistence

    func testSaveLoadRoundTrip() {
        let original = state()
        original.save(to: suite)

        let loaded = WeeklyGoalWidgetState.load(from: suite)

        XCTAssertEqual(loaded, original)
    }

    func testLoadReturnsNilWhenNothingPublished() {
        XCTAssertNil(WeeklyGoalWidgetState.load(from: suite))
    }

    func testLoadReturnsNilOnCorruptPayload() {
        suite.set(Data("not json".utf8), forKey: SharedDefaults.Key.weeklyGoalSnapshot)

        XCTAssertNil(WeeklyGoalWidgetState.load(from: suite))
    }

    func testSaveOverwritesPreviousSnapshot() {
        state(sessions: 1).save(to: suite)
        state(sessions: 3).save(to: suite)

        XCTAssertEqual(WeeklyGoalWidgetState.load(from: suite)?.thisWeekSessions, 3)
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
