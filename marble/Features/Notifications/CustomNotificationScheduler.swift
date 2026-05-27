import Foundation
import UserNotifications

enum CustomNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
}

struct CustomNotificationScheduleRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let weekday: Int
    let hour: Int
    let minute: Int
}

enum CustomNotificationScheduleOutcome: Equatable {
    case disabled
    case invalid
    case denied
    case scheduled(Int)
}

@MainActor
protocol CustomNotificationSchedulingClient {
    func authorizationStatus() async -> CustomNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: CustomNotificationScheduleRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

@MainActor
struct CustomNotificationScheduler {
    let client: CustomNotificationSchedulingClient

    init(client: CustomNotificationSchedulingClient) {
        self.client = client
    }

    static func live() -> CustomNotificationScheduler {
        CustomNotificationScheduler(client: defaultClient())
    }

    func authorizationStatus() async -> CustomNotificationAuthorizationStatus {
        await client.authorizationStatus()
    }

    @discardableResult
    func requestAuthorization() async -> CustomNotificationAuthorizationStatus {
        do {
            return try await client.requestAuthorization() ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    @discardableResult
    func sync(_ notification: CustomNotification) async -> CustomNotificationScheduleOutcome {
        client.removePendingRequests(withIdentifiers: CustomNotification.requestIdentifiers(for: notification.id))

        guard notification.isEnabled else { return .disabled }
        let requests = Self.requests(for: notification)
        guard !requests.isEmpty else { return .invalid }

        let status = await permissionStatusForScheduling()
        guard status == .authorized else { return .denied }

        do {
            for request in requests {
                try await client.add(request)
            }
            return .scheduled(requests.count)
        } catch {
            return .invalid
        }
    }

    func remove(_ notification: CustomNotification) {
        client.removePendingRequests(withIdentifiers: CustomNotification.requestIdentifiers(for: notification.id))
    }

    static func requests(for notification: CustomNotification) -> [CustomNotificationScheduleRequest] {
        guard notification.isEnabled, notification.isValidSchedule else { return [] }
        return notification.selectedWeekdays.map { weekday in
            CustomNotificationScheduleRequest(
                identifier: CustomNotification.requestIdentifier(for: notification.id, weekday: weekday),
                title: CustomNotification.title,
                body: notification.trimmedMessage,
                weekday: weekday.calendarWeekday,
                hour: notification.hour,
                minute: notification.minute
            )
        }
    }

    private func permissionStatusForScheduling() async -> CustomNotificationAuthorizationStatus {
        let status = await client.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await requestAuthorization()
    }

    private static func defaultClient() -> CustomNotificationSchedulingClient {
        if TestHooks.isUITesting {
            return TestNotificationSchedulingClient()
        }
        return UserNotificationSchedulingClient()
    }
}

private struct UserNotificationSchedulingClient: CustomNotificationSchedulingClient {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> CustomNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: CustomNotificationScheduleRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        var components = DateComponents()
        components.calendar = Calendar.current
        components.weekday = request.weekday
        components.hour = request.hour
        components.minute = request.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let notificationRequest = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        try await center.add(notificationRequest)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private struct TestNotificationSchedulingClient: CustomNotificationSchedulingClient {
    func authorizationStatus() async -> CustomNotificationAuthorizationStatus {
        configuredStatus
    }

    func requestAuthorization() async throws -> Bool {
        configuredStatus != .denied
    }

    func add(_ request: CustomNotificationScheduleRequest) async throws {}

    func removePendingRequests(withIdentifiers identifiers: [String]) {}

    private var configuredStatus: CustomNotificationAuthorizationStatus {
        switch TestHooks.notificationAuthorizationStatus?.lowercased() {
        case "denied":
            return .denied
        case "notdetermined", "not_determined":
            return .notDetermined
        default:
            return .authorized
        }
    }
}
