import UserNotifications

/// Notification removal performs synchronous XPC even though it returns Void.
/// Run it away from the UI actor; callers retain their schedule/cancel ordering.
nonisolated enum NotificationDelivery {
    @concurrent
    static func removePending(
        identifiers: [String],
        remove: @Sendable ([String]) -> Void = {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0)
        }
    ) async {
        remove(identifiers)
    }
}
