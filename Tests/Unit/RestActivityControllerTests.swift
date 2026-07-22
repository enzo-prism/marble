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
        let client = FakeRestLiveActivityClient()
        let controller = RestActivityController(liveActivities: client)
        let endsAt = Date(timeIntervalSince1970: 1_700_000_000)
        controller.beginRestSession(exerciseName: "Bench Press", endsAt: endsAt)

        controller.pruneExpiredRest(now: endsAt.addingTimeInterval(-1))
        XCTAssertNotNil(controller.activeRest, "A rest still counting down must survive a prune")

        controller.pruneExpiredRest(now: endsAt)
        XCTAssertNil(controller.activeRest, "An elapsed rest must be cleared by a prune")
    }

    // MARK: - System Live Activity invariant

    func testReconciliationKeepsOnlyLatestUnexpiredActivity() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            RestLiveActivitySnapshot(
                id: "expired",
                exerciseName: "Deadlift",
                endsAt: now.addingTimeInterval(-1),
                isOngoing: true
            ),
            RestLiveActivitySnapshot(
                id: "older",
                exerciseName: "Good Morning",
                endsAt: now.addingTimeInterval(30),
                isOngoing: true
            ),
            RestLiveActivitySnapshot(
                id: "latest",
                exerciseName: "Squat",
                endsAt: now.addingTimeInterval(90),
                isOngoing: true
            ),
            RestLiveActivitySnapshot(
                id: "ended",
                exerciseName: "Bench Press",
                endsAt: now.addingTimeInterval(120),
                isOngoing: false
            )
        ]

        let plan = RestActivityController.reconciliationPlan(for: snapshots, now: now)

        XCTAssertEqual(plan.keeper?.id, "latest")
        XCTAssertEqual(plan.activityIDsToEnd, ["ended", "expired", "older"])
    }

    func testReconciliationPrefersNewestCreationEvenWhenItsRestEndsSooner() {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let snapshots = [
            RestLiveActivitySnapshot(
                id: "old-long-rest",
                exerciseName: "Good Morning",
                endsAt: now.addingTimeInterval(300),
                startedAt: now.addingTimeInterval(-60),
                isOngoing: true
            ),
            RestLiveActivitySnapshot(
                id: "new-short-rest",
                exerciseName: "Squat",
                endsAt: now.addingTimeInterval(60),
                startedAt: now,
                isOngoing: true
            )
        ]

        let plan = RestActivityController.reconciliationPlan(for: snapshots, now: now)

        XCTAssertEqual(plan.keeper?.id, "new-short-rest")
        XCTAssertEqual(plan.activityIDsToEnd, ["old-long-rest"])
    }

    @MainActor
    func testRepeatedStartsNeverCreateMoreThanOneLiveActivity() async {
        let client = FakeRestLiveActivityClient()
        let controller = RestActivityController(liveActivities: client)
        let now = Date(timeIntervalSince1970: 4_000_000_000)

        for index in 0..<10 {
            controller.startRest(exerciseName: "Set \(index)", restSeconds: 90, now: now)
            await controller.waitForPendingLiveActivityOperation()
        }

        XCTAssertEqual(client.currentSnapshots.count, 1)
        XCTAssertEqual(client.currentSnapshots.first?.exerciseName, "Set 9")
        XCTAssertEqual(client.maximumConcurrentActivityCount, 1)
        XCTAssertEqual(client.requestCount, 10)
    }

    @MainActor
    func testRapidStartsOnlyRequestTheLatestTimer() async {
        let client = FakeRestLiveActivityClient()
        let controller = RestActivityController(liveActivities: client)
        let now = Date(timeIntervalSince1970: 4_000_000_000)

        controller.startRest(exerciseName: "Bench Press", restSeconds: 60, now: now)
        controller.startRest(exerciseName: "Good Morning", restSeconds: 75, now: now)
        controller.startRest(exerciseName: "Squat", restSeconds: 90, now: now)
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(client.currentSnapshots.map(\.exerciseName), ["Squat"])
        XCTAssertEqual(client.maximumConcurrentActivityCount, 1)
    }

    @MainActor
    func testRelaunchReconciliationCollapsesLegacyPileAndRestoresOneTimer() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(id: "expired", exerciseName: "Deadlift", endsAt: now.addingTimeInterval(-20), isOngoing: true),
            .init(id: "older", exerciseName: "Good Morning", endsAt: now.addingTimeInterval(30), isOngoing: true),
            .init(id: "keeper", exerciseName: "Squat", endsAt: now.addingTimeInterval(90), isOngoing: true)
        ])
        let controller = RestActivityController(liveActivities: client)

        controller.reconcileLiveActivities(now: now)
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertEqual(client.currentSnapshots.map(\.id), ["keeper"])
        XCTAssertEqual(
            controller.activeRest,
            ActiveRest(exerciseName: "Squat", endsAt: now.addingTimeInterval(90))
        )
    }

    @MainActor
    func testRelaunchWithOnlyExpiredActivitiesDismissesEveryCard() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(id: "one", exerciseName: "Squat", endsAt: now.addingTimeInterval(-10), isOngoing: true),
            .init(id: "two", exerciseName: "Good Morning", endsAt: now, isOngoing: true)
        ])
        let controller = RestActivityController(liveActivities: client)

        controller.reconcileLiveActivities(now: now)
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertNil(controller.activeRest)
        XCTAssertTrue(client.currentSnapshots.isEmpty)
        XCTAssertEqual(Set(client.endedActivityIDs), Set(["one", "two"]))
    }

    @MainActor
    func testNaturalCompletionImmediatelyDismissesTheSystemActivity() async {
        let client = FakeRestLiveActivityClient()
        let controller = RestActivityController(liveActivities: client)
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let endsAt = now.addingTimeInterval(90)
        controller.startRest(exerciseName: "Squat", restSeconds: 90, now: now)
        await controller.waitForPendingLiveActivityOperation()

        controller.completeRest(endingAt: endsAt)
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertNil(controller.activeRest)
        XCTAssertTrue(client.currentSnapshots.isEmpty)
        XCTAssertEqual(client.endedActivityIDs.count, 1)
    }

    @MainActor
    func testSupersededExpiryCannotEndReplacementTimer() async {
        let client = FakeRestLiveActivityClient()
        let controller = RestActivityController(liveActivities: client)
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let firstEnd = now.addingTimeInterval(60)
        let secondEnd = now.addingTimeInterval(120)

        controller.startRest(exerciseName: "Good Morning", restSeconds: 60, now: now)
        await controller.waitForPendingLiveActivityOperation()
        controller.startRest(exerciseName: "Squat", restSeconds: 120, now: now)
        await controller.waitForPendingLiveActivityOperation()

        controller.completeRest(endingAt: firstEnd)
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertEqual(controller.activeRest, ActiveRest(exerciseName: "Squat", endsAt: secondEnd))
        XCTAssertEqual(client.currentSnapshots.map(\.exerciseName), ["Squat"])
    }

    @MainActor
    func testExtendAfterProcessRelaunchTargetsExactActivityWithoutCreatingAnother() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let originalEnd = now.addingTimeInterval(60)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(id: "current", exerciseName: "Squat", endsAt: originalEnd, isOngoing: true)
        ])
        let controller = RestActivityController(liveActivities: client)

        controller.extend(by: 30, now: now, activityID: "current")
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertEqual(client.requestCount, 0)
        XCTAssertEqual(client.currentSnapshots.count, 1)
        XCTAssertEqual(client.currentSnapshots.first?.endsAt, originalEnd.addingTimeInterval(30))
        XCTAssertEqual(controller.activeRest?.endsAt, originalEnd.addingTimeInterval(30))
    }

    @MainActor
    func testRapidExtendTapsAccumulateWhileActivityKitUpdateIsDelayed() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let originalEnd = now.addingTimeInterval(60)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(
                id: "current",
                exerciseName: "Squat",
                endsAt: originalEnd,
                startedAt: now,
                isOngoing: true
            )
        ])
        client.updateDelay = .milliseconds(20)
        let controller = RestActivityController(liveActivities: client)
        controller.reconcileLiveActivities(now: now)

        controller.extend(by: 30, now: now, activityID: "current")
        controller.extend(by: 30, now: now, activityID: "current")
        controller.extend(by: 30, now: now, activityID: "current")
        await controller.waitForPendingLiveActivityOperation()

        let expectedEnd = originalEnd.addingTimeInterval(90)
        XCTAssertEqual(controller.activeRest?.endsAt, expectedEnd)
        XCTAssertEqual(client.currentSnapshots.first?.endsAt, expectedEnd)
        XCTAssertEqual(client.updatedEnds.last, expectedEnd)
    }

    @MainActor
    func testForegroundReconciliationCannotRegressAnInFlightExtension() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let originalEnd = now.addingTimeInterval(60)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(
                id: "current",
                exerciseName: "Squat",
                endsAt: originalEnd,
                startedAt: now,
                isOngoing: true
            )
        ])
        client.updateDelay = .milliseconds(20)
        let controller = RestActivityController(liveActivities: client)
        controller.reconcileLiveActivities(now: now)

        controller.extend(by: 30, now: now, activityID: "current")
        controller.reconcileLiveActivities(now: now)

        let expectedEnd = originalEnd.addingTimeInterval(30)
        XCTAssertEqual(controller.activeRest?.endsAt, expectedEnd)
        await controller.waitForPendingLiveActivityOperation()
        XCTAssertEqual(controller.activeRest?.endsAt, expectedEnd)
        XCTAssertEqual(client.currentSnapshots.first?.endsAt, expectedEnd)
    }

    @MainActor
    func testEndOnOldDuplicatePreservesTheNewerCurrentTimer() async {
        let now = Date(timeIntervalSince1970: 4_000_000_000)
        let client = FakeRestLiveActivityClient(snapshots: [
            .init(id: "old", exerciseName: "Good Morning", endsAt: now.addingTimeInterval(30), isOngoing: true),
            .init(id: "current", exerciseName: "Squat", endsAt: now.addingTimeInterval(90), isOngoing: true)
        ])
        let controller = RestActivityController(liveActivities: client)

        controller.cancelRest(activityID: "old")
        await controller.waitForPendingLiveActivityOperation()

        XCTAssertEqual(client.currentSnapshots.map(\.id), ["current"])
        XCTAssertEqual(controller.activeRest?.exerciseName, "Squat")
    }
}

@MainActor
private final class FakeRestLiveActivityClient: RestLiveActivityClient {
    var activitiesEnabled = true
    private(set) var currentSnapshots: [RestLiveActivitySnapshot]
    private(set) var endedActivityIDs: [String] = []
    private(set) var requestCount = 0
    private(set) var maximumConcurrentActivityCount: Int
    private(set) var updatedEnds: [Date] = []
    var updateDelay: Duration?

    init(snapshots: [RestLiveActivitySnapshot] = []) {
        currentSnapshots = snapshots
        maximumConcurrentActivityCount = snapshots.count
    }

    func snapshots() -> [RestLiveActivitySnapshot] {
        currentSnapshots
    }

    func request(exerciseName: String, endsAt: Date, startedAt: Date) throws -> String {
        requestCount += 1
        let id = "requested-\(requestCount)"
        currentSnapshots.append(
            RestLiveActivitySnapshot(
                id: id,
                exerciseName: exerciseName,
                endsAt: endsAt,
                startedAt: startedAt,
                isOngoing: true
            )
        )
        maximumConcurrentActivityCount = max(maximumConcurrentActivityCount, currentSnapshots.count)
        return id
    }

    func update(activityID: String, endsAt: Date) async {
        if let updateDelay {
            try? await Task.sleep(for: updateDelay)
        }
        guard let index = currentSnapshots.firstIndex(where: { $0.id == activityID }) else { return }
        let current = currentSnapshots[index]
        updatedEnds.append(endsAt)
        currentSnapshots[index] = RestLiveActivitySnapshot(
            id: current.id,
            exerciseName: current.exerciseName,
            endsAt: endsAt,
            startedAt: current.startedAt,
            isOngoing: current.isOngoing
        )
    }

    func endImmediately(activityID: String) async {
        guard currentSnapshots.contains(where: { $0.id == activityID }) else { return }
        endedActivityIDs.append(activityID)
        currentSnapshots.removeAll { $0.id == activityID }
    }
}
