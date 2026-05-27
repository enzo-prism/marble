import Foundation
import SwiftData

@Model
final class CustomNotification {
    @Attribute(.unique) var id: UUID
    var message: String
    var hour: Int
    var minute: Int
    var weekdayMask: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        message: String,
        hour: Int = 9,
        minute: Int = 0,
        weekdayMask: Int = CustomNotification.defaultWeekdayMask,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.hour = hour
        self.minute = minute
        self.weekdayMask = weekdayMask
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CustomNotification {
    static let maximumCount = 10
    static let title = "Marble"
    static let requestIdentifierPrefix = "custom-notification"
    static let defaultWeekdayMask = mask(for: Set(Weekday.allCases))

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedWeekdays: [Weekday] {
        Weekday.allCases.filter { includes($0) }
    }

    var isValidSchedule: Bool {
        !trimmedMessage.isEmpty && !selectedWeekdays.isEmpty && (0..<24).contains(hour) && (0..<60).contains(minute)
    }

    func includes(_ weekday: Weekday) -> Bool {
        weekdayMask & weekday.notificationBitMask != 0
    }

    func setWeekdays(_ weekdays: Set<Weekday>) {
        weekdayMask = Self.mask(for: weekdays)
    }

    func setTime(from date: Date, calendar: Calendar = .current) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }

    func timeDate(reference: Date = AppEnvironment.now, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? reference
    }

    static func mask(for weekdays: Set<Weekday>) -> Int {
        weekdays.reduce(0) { partialResult, weekday in
            partialResult | weekday.notificationBitMask
        }
    }

    static func requestIdentifier(for id: UUID, weekday: Weekday) -> String {
        "\(requestIdentifierPrefix)-\(id.uuidString)-\(weekday.rawValue)"
    }

    static func requestIdentifiers(for id: UUID) -> [String] {
        Weekday.allCases.map { requestIdentifier(for: id, weekday: $0) }
    }
}

extension Weekday {
    var notificationBitMask: Int {
        1 << (rawValue - 1)
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }
}
