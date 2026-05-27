import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class NotificationsSnapshotTests: SnapshotTestCase {
    func testNotificationsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = NavigationStack {
            NotificationsView(scheduler: snapshotScheduler)
        }
        .modelContainer(container)
        assertSnapshot(view, named: "Notifications_Empty")
    }

    func testNotificationsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        seedNotifications(count: 3, in: context)

        let view = NavigationStack {
            NotificationsView(scheduler: snapshotScheduler)
        }
        .modelContainer(container)
        assertSnapshot(view, named: "Notifications_Populated")
    }

    func testNotificationsMaxLimit() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        seedNotifications(count: CustomNotification.maximumCount, in: context)

        let view = NavigationStack {
            NotificationsView(scheduler: snapshotScheduler)
        }
        .modelContainer(container)
        assertSnapshot(view, named: "Notifications_MaxLimit")
    }

    func testNotificationEditor() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = NavigationStack {
            NotificationEditorView(notification: nil, scheduler: snapshotScheduler)
        }
        .modelContainer(container)
        assertSnapshot(view, named: "NotificationEditor_New")
    }

    private var snapshotScheduler: CustomNotificationScheduler {
        CustomNotificationScheduler(client: SnapshotNotificationSchedulingClient())
    }

    private func seedNotifications(count: Int, in context: ModelContext) {
        for index in 0..<count {
            let notification = CustomNotification(
                message: "Reminder \(index + 1)",
                hour: 7 + (index % 5),
                minute: index % 2 == 0 ? 0 : 30,
                weekdayMask: index % 2 == 0
                    ? CustomNotification.mask(for: [.monday, .wednesday, .friday])
                    : CustomNotification.mask(for: [.tuesday, .thursday]),
                isEnabled: index % 3 != 0,
                createdAt: SnapshotFixtures.now.addingTimeInterval(TimeInterval(index)),
                updatedAt: SnapshotFixtures.now.addingTimeInterval(TimeInterval(index))
            )
            context.insert(notification)
        }
        try? context.save()
    }
}

@MainActor
private struct SnapshotNotificationSchedulingClient: CustomNotificationSchedulingClient {
    func authorizationStatus() async -> CustomNotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func add(_ request: CustomNotificationScheduleRequest) async throws {}

    func removePendingRequests(withIdentifiers identifiers: [String]) {}
}
