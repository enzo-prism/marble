import SwiftData
import XCTest
@testable import marble

@MainActor
final class CustomNotificationTests: MarbleTestCase {
    func testWeekdayMaskAndCalendarMapping() {
        let mask = CustomNotification.mask(for: [.monday, .wednesday, .sunday])
        let notification = CustomNotification(message: "Train", weekdayMask: mask)

        XCTAssertTrue(notification.includes(.monday))
        XCTAssertTrue(notification.includes(.wednesday))
        XCTAssertTrue(notification.includes(.sunday))
        XCTAssertFalse(notification.includes(.tuesday))
        XCTAssertEqual(Weekday.sunday.calendarWeekday, 1)
        XCTAssertEqual(Weekday.monday.calendarWeekday, 2)
        XCTAssertEqual(Weekday.saturday.calendarWeekday, 7)
    }

    func testScheduleRequestsUseTrimmedMessageTimeAndWeekdays() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let notification = CustomNotification(
            id: id,
            message: "  Log workout  ",
            hour: 7,
            minute: 30,
            weekdayMask: CustomNotification.mask(for: [.monday, .sunday])
        )

        let requests = CustomNotificationScheduler.requests(for: notification)

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.identifier), [
            "custom-notification-11111111-1111-1111-1111-111111111111-1",
            "custom-notification-11111111-1111-1111-1111-111111111111-7"
        ])
        XCTAssertEqual(requests.map(\.body), ["Log workout", "Log workout"])
        XCTAssertEqual(requests.map(\.weekday), [2, 1])
        XCTAssertEqual(requests.map(\.hour), [7, 7])
        XCTAssertEqual(requests.map(\.minute), [30, 30])
    }

    func testInvalidOrDisabledNotificationProducesNoRequests() {
        let emptyMessage = CustomNotification(message: " ", weekdayMask: CustomNotification.mask(for: [.monday]))
        let noDays = CustomNotification(message: "Train", weekdayMask: 0)
        let disabled = CustomNotification(message: "Train", isEnabled: false)

        XCTAssertTrue(CustomNotificationScheduler.requests(for: emptyMessage).isEmpty)
        XCTAssertTrue(CustomNotificationScheduler.requests(for: noDays).isEmpty)
        XCTAssertTrue(CustomNotificationScheduler.requests(for: disabled).isEmpty)
    }

    func testMaximumNotificationCountIsTen() throws {
        let context = makeInMemoryContext()
        for index in 0..<CustomNotification.maximumCount {
            context.insert(CustomNotification(message: "Reminder \(index)", createdAt: now, updatedAt: now))
        }
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<CustomNotification>())
        XCTAssertEqual(count, 10)
        XCTAssertEqual(CustomNotification.maximumCount, 10)
    }
}

@MainActor
final class CustomNotificationSchedulerTests: XCTestCase {
    func testSyncRemovesAllWeekdaysThenSchedulesSelectedWeekdays() async {
        let client = RecordingNotificationSchedulingClient(status: .authorized)
        let scheduler = CustomNotificationScheduler(client: client)
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let notification = CustomNotification(
            id: id,
            message: "Lift",
            hour: 18,
            minute: 15,
            weekdayMask: CustomNotification.mask(for: [.tuesday, .thursday])
        )

        let outcome = await scheduler.sync(notification)

        XCTAssertEqual(outcome, .scheduled(2))
        XCTAssertEqual(client.removedIdentifiers, CustomNotification.requestIdentifiers(for: id))
        XCTAssertEqual(client.addedRequests.map(\.weekday), [3, 5])
        XCTAssertEqual(client.addedRequests.map(\.identifier), [
            "custom-notification-22222222-2222-2222-2222-222222222222-2",
            "custom-notification-22222222-2222-2222-2222-222222222222-4"
        ])
    }

    func testSyncRequestsPermissionWhenNotDetermined() async {
        let client = RecordingNotificationSchedulingClient(status: .notDetermined, requestResult: true)
        let scheduler = CustomNotificationScheduler(client: client)
        let notification = CustomNotification(message: "Move", weekdayMask: CustomNotification.mask(for: [.monday]))

        let outcome = await scheduler.sync(notification)

        XCTAssertEqual(outcome, .scheduled(1))
        XCTAssertEqual(client.requestAuthorizationCallCount, 1)
        XCTAssertEqual(client.addedRequests.count, 1)
    }

    func testDeniedPermissionDoesNotSchedule() async {
        let client = RecordingNotificationSchedulingClient(status: .denied)
        let scheduler = CustomNotificationScheduler(client: client)
        let notification = CustomNotification(message: "Move", weekdayMask: CustomNotification.mask(for: [.monday]))

        let outcome = await scheduler.sync(notification)

        XCTAssertEqual(outcome, .denied)
        XCTAssertTrue(client.addedRequests.isEmpty)
    }
}

@MainActor
private final class RecordingNotificationSchedulingClient: CustomNotificationSchedulingClient {
    var status: CustomNotificationAuthorizationStatus
    var requestResult: Bool
    var addedRequests: [CustomNotificationScheduleRequest] = []
    var removedIdentifiers: [String] = []
    var requestAuthorizationCallCount = 0

    init(status: CustomNotificationAuthorizationStatus, requestResult: Bool = false) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> CustomNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        status = requestResult ? .authorized : .denied
        return requestResult
    }

    func add(_ request: CustomNotificationScheduleRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers = identifiers
    }
}
