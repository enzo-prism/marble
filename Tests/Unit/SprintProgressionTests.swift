import Foundation
import XCTest
@testable import marble

final class SprintProgressionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    private let timeTarget = SprintTargetTenths(lowerTenths: 85, upperTenths: 85)
    private let rangeTarget = SprintTargetTenths(lowerTenths: 145, upperTenths: 160)

    func testNoSuggestionUnderTwoQualifyingSessions() {
        XCTAssertNil(SprintProgression.suggestion(target: timeTarget, repetitionCount: 4, sessions: []))
        XCTAssertNil(SprintProgression.suggestion(
            target: timeTarget,
            repetitionCount: 4,
            sessions: [.init(day: day(0), scoredReps: 4, hitReps: 4)]
        ))
    }

    func testSuggestionAfterTwoStrongSessionsTimeMode() {
        let hint = SprintProgression.suggestion(
            target: timeTarget,
            repetitionCount: 4,
            sessions: [
                .init(day: day(1), scoredReps: 4, hitReps: 4),
                .init(day: day(0), scoredReps: 5, hitReps: 4)
            ]
        )
        XCTAssertEqual(hint, "Hit in each of your last 2 sessions — try 8.3s or faster.")
    }

    func testSuggestionTightensRangeMode() {
        let hint = SprintProgression.suggestion(
            target: rangeTarget,
            repetitionCount: 4,
            sessions: [
                .init(day: day(1), scoredReps: 4, hitReps: 4),
                .init(day: day(0), scoredReps: 4, hitReps: 4)
            ]
        )
        XCTAssertEqual(hint, "Hit in each of your last 2 sessions — try tightening the range to 14.5–15.8s.")
    }

    func testNoSuggestionWhenARecentSessionMissedTheBar() {
        XCTAssertNil(SprintProgression.suggestion(
            target: timeTarget,
            repetitionCount: 4,
            sessions: [
                .init(day: day(1), scoredReps: 4, hitReps: 4),
                .init(day: day(0), scoredReps: 4, hitReps: 3) // 75% < 80%
            ]
        ))
    }

    func testNoSuggestionWhenSessionTooSmall() {
        // One-rep cameos can't tighten the plan: minimum is max(2, reps/2).
        XCTAssertNil(SprintProgression.suggestion(
            target: timeTarget,
            repetitionCount: 4,
            sessions: [
                .init(day: day(1), scoredReps: 1, hitReps: 1),
                .init(day: day(0), scoredReps: 4, hitReps: 4)
            ]
        ))
    }

    func testNoSuggestionWhenStepWouldReachZero() {
        let tiny = SprintTargetTenths(lowerTenths: 2, upperTenths: 2)
        XCTAssertNil(SprintProgression.suggestion(
            target: tiny,
            repetitionCount: 4,
            sessions: [
                .init(day: day(1), scoredReps: 4, hitReps: 4),
                .init(day: day(0), scoredReps: 4, hitReps: 4)
            ]
        ))
    }

    func testSessionsGroupByDayNewestFirstAndJudgeFrozenTargets() {
        // Two reps day 0 (one hit against its FROZEN target), three reps day 1.
        let details: [(performedAt: Date, tenths: Int, target: SprintTargetTenths)] = [
            (day(0), 84, timeTarget),                                  // hit
            (day(0), 90, SprintTargetTenths(lowerTenths: 95, upperTenths: 95)), // hit vs old target
            (day(1), 84, timeTarget),                                  // hit
            (day(1), 86, timeTarget),                                  // miss
            (day(1), 85, timeTarget)                                   // hit
        ]
        let sessions = SprintProgression.sessions(details: details, calendar: calendar)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.scoredReps, 3, "Newest day first")
        XCTAssertEqual(sessions.first?.hitReps, 2)
        XCTAssertEqual(sessions.last?.scoredReps, 2)
        XCTAssertEqual(sessions.last?.hitReps, 2)
    }
}

final class SprintTrendsBuilderTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    // A fixed Wednesday so week bucketing is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func rep(daysAgo: Int, meters: Double, tenths: Int, hit: Bool?) -> SprintTrendsBuilder.Rep {
        SprintTrendsBuilder.Rep(
            performedAt: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400),
            distanceMeters: meters,
            tenths: tenths,
            isHit: hit
        )
    }

    func testEmptyInputDerivesEmpty() {
        XCTAssertTrue(SprintTrendsBuilder.derive(reps: [], now: now, calendar: calendar).isEmpty)
    }

    func testFocusDistanceIsMostLoggedAndBestTimesArePerDayMinimums() {
        let reps = [
            rep(daysAgo: 0, meters: 60, tenths: 88, hit: true),
            rep(daysAgo: 0, meters: 60, tenths: 84, hit: true),
            rep(daysAgo: 7, meters: 60, tenths: 90, hit: false),
            rep(daysAgo: 3, meters: 150, tenths: 205, hit: true)
        ]
        let derived = SprintTrendsBuilder.derive(reps: reps, now: now, calendar: calendar)

        XCTAssertEqual(derived.focusDistanceMeters, 60)
        XCTAssertEqual(derived.bestTimePoints.count, 2)
        XCTAssertEqual(derived.bestTimePoints.last?.tenths, 84, "Same-day best is the minimum")
        XCTAssertEqual(derived.recordPoint?.tenths, 84)
    }

    func testWeeklyBarsCountOnlyScoredRepsInsideTheWindow() {
        let reps = [
            rep(daysAgo: 0, meters: 60, tenths: 84, hit: true),
            rep(daysAgo: 0, meters: 60, tenths: 90, hit: false),
            rep(daysAgo: 0, meters: 60, tenths: 90, hit: nil), // unscored: excluded
            rep(daysAgo: 70, meters: 60, tenths: 84, hit: true) // outside 8 weeks
        ]
        let derived = SprintTrendsBuilder.derive(reps: reps, now: now, calendar: calendar)

        XCTAssertEqual(derived.weekBars.count, 1)
        XCTAssertEqual(derived.weekBars.first?.scored, 2)
        XCTAssertEqual(derived.weekBars.first?.hits, 1)
        XCTAssertEqual(derived.weekBars.first?.hitRatePercent ?? 0, 50, accuracy: 0.01)
    }

    func testDistanceTieBreaksToShorter() {
        let reps = [
            rep(daysAgo: 0, meters: 150, tenths: 200, hit: true),
            rep(daysAgo: 1, meters: 60, tenths: 88, hit: true)
        ]
        let derived = SprintTrendsBuilder.derive(reps: reps, now: now, calendar: calendar)
        XCTAssertEqual(derived.focusDistanceMeters, 60)
    }
}
