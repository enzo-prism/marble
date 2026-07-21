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
        generatedAt: Date? = nil,
        weekStart: Date? = nil
    ) -> WeeklyGoalWidgetState {
        WeeklyGoalWidgetState(
            target: target,
            thisWeekSessions: sessions,
            streakWeeks: streak,
            flexTokens: flex,
            stateRaw: stateRaw,
            weekStart: weekStart ?? reference,
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

    // MARK: Week identity

    /// Pinned to UTC with a Sunday first weekday so these cases can't drift
    /// with the test machine's locale.
    private var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    private func utc(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .gmt
        return try XCTUnwrap(formatter.date(from: iso))
    }

    /// Load-bearing: the app writes `weekStart` with `TrendsDateHelper`, the
    /// widget compares against `WeeklyGoalWidgetState.startOfWeek`. If these
    /// two ever disagree the widget silently renders the neutral card forever.
    func testStartOfWeekMatchesTheAppsTrendsHelper() throws {
        let calendar = weekCalendar
        var probe = try utc("2025-01-01T00:00:00Z")

        for _ in 0..<40 {
            XCTAssertEqual(
                WeeklyGoalWidgetState.startOfWeek(for: probe, calendar: calendar),
                TrendsDateHelper.startOfWeek(for: probe, calendar: calendar),
                "week anchors diverged at \(probe)"
            )
            probe = probe.addingTimeInterval(60 * 60 * 9)
        }
    }

    func testSnapshotFromTheCurrentWeekIsRenderable() throws {
        // 2025-01-12 is a Sunday; 2025-01-15 is the Wednesday inside that week.
        let weekStart = try utc("2025-01-12T00:00:00Z")
        let midweek = try utc("2025-01-15T09:30:00Z")
        let snapshot = state(generatedAt: midweek, weekStart: weekStart)

        XCTAssertTrue(snapshot.describesWeek(containing: midweek, calendar: weekCalendar))
        XCTAssertTrue(snapshot.isRenderable(now: midweek, calendar: weekCalendar))
    }

    /// **The regression.** Backgrounding the app Saturday 23:00 having hit 4 of
    /// 3 sessions used to leave the Lock Screen reading "4 of 3 · Target hit"
    /// on the Sunday of a week with zero sessions: the snapshot is one hour
    /// old, so the age check alone says it is perfectly fresh.
    func testSaturdayNightSnapshotIsNotRenderableOnceSundayStartsANewWeek() throws {
        let lastWeekStart = try utc("2025-01-12T00:00:00Z")
        let saturdayNight = try utc("2025-01-18T23:00:00Z")
        let sundayMidnight = try utc("2025-01-19T00:00:00Z")
        let snapshot = state(
            target: 3,
            sessions: 4,
            stateRaw: "hit",
            generatedAt: saturdayNight,
            weekStart: lastWeekStart
        )

        // Only an hour old — the 8-day check cannot catch this on its own.
        XCTAssertFalse(snapshot.isStale(now: sundayMidnight))
        XCTAssertFalse(snapshot.describesWeek(containing: sundayMidnight, calendar: weekCalendar))
        XCTAssertFalse(snapshot.isRenderable(now: sundayMidnight, calendar: weekCalendar))
    }

    /// The same mismatch at every later point in the new week, not just the
    /// midnight instant.
    func testWeekMismatchBlocksRenderingForTheWholeFollowingWeek() throws {
        let lastWeekStart = try utc("2025-01-12T00:00:00Z")
        let snapshot = state(generatedAt: try utc("2025-01-18T23:00:00Z"), weekStart: lastWeekStart)

        for iso in [
            "2025-01-19T00:00:00Z",
            "2025-01-19T12:00:00Z",
            "2025-01-22T08:00:00Z",
            "2025-01-25T23:59:59Z"
        ] {
            let now = try utc(iso)
            XCTAssertFalse(snapshot.isRenderable(now: now, calendar: weekCalendar), "still rendering at \(iso)")
        }
    }

    /// Staleness stays as the second line of defence: a snapshot claiming the
    /// current week but generated well over a week ago is still refused.
    func testStalenessStillBlocksRenderingWhenTheWeekMatches() throws {
        let weekStart = try utc("2025-01-12T00:00:00Z")
        let midweek = try utc("2025-01-15T09:30:00Z")
        let snapshot = state(
            generatedAt: midweek.addingTimeInterval(-9 * 24 * 60 * 60),
            weekStart: weekStart
        )

        XCTAssertTrue(snapshot.describesWeek(containing: midweek, calendar: weekCalendar))
        XCTAssertTrue(snapshot.isStale(now: midweek))
        XCTAssertFalse(snapshot.isRenderable(now: midweek, calendar: weekCalendar))
    }

    /// A snapshot published earlier the same Saturday must keep rendering —
    /// the fix must not blank the widget mid-week.
    func testSnapshotStaysRenderableUpToTheLastSecondOfItsOwnWeek() throws {
        let weekStart = try utc("2025-01-12T00:00:00Z")
        let snapshot = state(generatedAt: try utc("2025-01-13T07:00:00Z"), weekStart: weekStart)

        XCTAssertTrue(snapshot.isRenderable(now: try utc("2025-01-18T23:59:59Z"), calendar: weekCalendar))
    }

    /// `weekStart` is normalised on both sides, so a snapshot whose stored
    /// anchor is not exactly midnight (or was written under another time zone)
    /// still resolves to the week it belongs to.
    func testUnnormalisedWeekStartStillResolvesToItsOwnWeek() throws {
        let midweek = try utc("2025-01-15T09:30:00Z")
        let snapshot = state(generatedAt: midweek, weekStart: try utc("2025-01-14T17:45:00Z"))

        XCTAssertTrue(snapshot.isRenderable(now: midweek, calendar: weekCalendar))
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
        // Gallery previews must not fall through to the neutral empty card —
        // including through the week-identity gate, since the placeholder
        // resolves its `weekStart` at first access rather than at epoch.
        XCTAssertFalse(placeholder.isStale(now: Date()))
        XCTAssertTrue(placeholder.isRenderable(now: Date()))
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
