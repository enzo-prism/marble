import XCTest
@testable import marble

/// Covers the pure decision/timing logic of the rest-timer Live Activity. The ActivityKit
/// runtime (requesting/ending activities) needs a device and user authorization, so it isn't
/// unit-testable; these tests pin the behaviour that decides *whether* and *until when* a
/// timer runs.
final class RestActivityControllerTests: XCTestCase {
    func testStartsOnlyWhenRestIsPositive() {
        XCTAssertTrue(RestActivityController.shouldStart(restSeconds: 90))
        XCTAssertTrue(RestActivityController.shouldStart(restSeconds: 1))
        XCTAssertFalse(RestActivityController.shouldStart(restSeconds: 0))
        XCTAssertFalse(RestActivityController.shouldStart(restSeconds: -30))
    }

    func testRestEndDateAddsRestToNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RestActivityController.restEndDate(restSeconds: 90, now: now), now.addingTimeInterval(90))
        XCTAssertEqual(RestActivityController.restEndDate(restSeconds: 0, now: now), now)
    }

    // MARK: - Extending a running rest ("+30s" on the Live Activity)

    func testExtendedEndAddsToTheCurrentEndNotToNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let currentEnd = now.addingTimeInterval(60)

        XCTAssertEqual(
            RestActivityController.extendedEnd(from: currentEnd, by: 30, now: now),
            now.addingTimeInterval(90),
            "Extending must build on the remaining rest, not restart it from now"
        )
    }

    func testExtendedEndAccumulatesAcrossRepeatedTaps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var end = now.addingTimeInterval(60)

        for _ in 0..<3 {
            end = RestActivityController.extendedEnd(from: end, by: 30, now: now)
        }

        XCTAssertEqual(end, now.addingTimeInterval(150), "Three +30s taps must add a full 90 seconds")
    }

    func testExtendedEndClampsAnAlreadyExpiredRestToNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredEnd = now.addingTimeInterval(-45)

        XCTAssertEqual(
            RestActivityController.extendedEnd(from: expiredEnd, by: 30, now: now),
            now.addingTimeInterval(30),
            "A tap on a stale render must extend from now, never land in the past"
        )
    }

    func testExtendedEndNeverReturnsAPastDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for offset in [-600.0, -1.0, 0.0, 1.0, 600.0] {
            let result = RestActivityController.extendedEnd(from: now.addingTimeInterval(offset), by: 30, now: now)
            XCTAssertGreaterThan(result, now, "extendedEnd must stay in the future (offset \(offset))")
        }
    }

    func testExtendedEndFromExactlyNowStartsFromNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RestActivityController.extendedEnd(from: now, by: 30, now: now), now.addingTimeInterval(30))
    }

    @MainActor
    func testExtendIsANoOpWhenNothingIsResting() {
        let controller = RestActivityController()

        controller.extend(by: 30, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertNil(controller.activeRest, "Extending an idle controller must not invent a rest")
    }

    @MainActor
    func testExtendRepublishesActiveRestKeepingTheExercise() {
        let controller = RestActivityController()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(600)
        controller.beginRestSession(exerciseName: "Bench Press", endsAt: endsAt)

        controller.extend(by: 30, now: now)

        XCTAssertEqual(
            controller.activeRest,
            ActiveRest(exerciseName: "Bench Press", endsAt: endsAt.addingTimeInterval(30))
        )
    }

    @MainActor
    func testRepeatedExtendCallsAccumulateOnTheController() {
        let controller = RestActivityController()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(600)
        controller.beginRestSession(exerciseName: "Squat", endsAt: endsAt)

        controller.extend(by: 30, now: now)
        controller.extend(by: 30, now: now)

        XCTAssertEqual(controller.activeRest?.endsAt, endsAt.addingTimeInterval(60))
    }

    // MARK: - In-app rest state (drives the tab-bar pill; no ActivityKit involved)

    @MainActor
    func testBeginRestSessionPublishesActiveRest() {
        let controller = RestActivityController()
        let endsAt = Date().addingTimeInterval(600)

        controller.beginRestSession(exerciseName: "Bench Press", endsAt: endsAt)

        XCTAssertEqual(controller.activeRest, ActiveRest(exerciseName: "Bench Press", endsAt: endsAt))
    }

    @MainActor
    func testBeginRestSessionReplacesPriorRest() {
        let controller = RestActivityController()
        let firstEnd = Date().addingTimeInterval(600)
        let secondEnd = Date().addingTimeInterval(900)

        controller.beginRestSession(exerciseName: "Bench Press", endsAt: firstEnd)
        controller.beginRestSession(exerciseName: "Squat", endsAt: secondEnd)

        XCTAssertEqual(controller.activeRest, ActiveRest(exerciseName: "Squat", endsAt: secondEnd))
    }

    @MainActor
    func testCancelRestClearsActiveRest() {
        let controller = RestActivityController()
        controller.beginRestSession(exerciseName: "Bench Press", endsAt: Date().addingTimeInterval(600))

        controller.cancelRest()

        XCTAssertNil(controller.activeRest)
    }

    @MainActor
    func testPruneExpiredRestClearsOnlyElapsedRests() {
        let controller = RestActivityController()
        let endsAt = Date(timeIntervalSince1970: 1_700_000_000)
        controller.beginRestSession(exerciseName: "Bench Press", endsAt: endsAt)

        controller.pruneExpiredRest(now: endsAt.addingTimeInterval(-1))
        XCTAssertNotNil(controller.activeRest, "A rest still counting down must survive a prune")

        controller.pruneExpiredRest(now: endsAt)
        XCTAssertNil(controller.activeRest, "An elapsed rest must be cleared by a prune")
    }
}
