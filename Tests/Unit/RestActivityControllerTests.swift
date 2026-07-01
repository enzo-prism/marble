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
