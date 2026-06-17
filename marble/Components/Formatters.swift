import Foundation

enum Formatters {
    static let weight: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let distance: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let dose: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let compactNumber: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        // Localized template rather than a fixed format string, so the weekday/month/day
        // ordering and separators follow the user's locale ("Wed, Jun 10" in en-US).
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter
    }()

    static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func compactNumberText(_ value: Double) -> String {
        let absoluteValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absoluteValue >= 1_000_000 {
            let formatted = compactNumber.string(from: NSNumber(value: absoluteValue / 1_000_000)) ?? "\(absoluteValue / 1_000_000)"
            return "\(sign)\(formatted)M"
        }
        if absoluteValue >= 1_000 {
            let formatted = compactNumber.string(from: NSNumber(value: absoluteValue / 1_000)) ?? "\(absoluteValue / 1_000)"
            return "\(sign)\(formatted)K"
        }
        return weight.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

enum DateHelper {
    static func dayLabel(for date: Date, now: Date = AppEnvironment.now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return Formatters.day.string(from: date)
    }

    static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func merge(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second
        return calendar.date(from: merged) ?? day
    }

    static func formattedDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        if minutes == 0 {
            return "\(remaining)s"
        }
        if remaining == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remaining)s"
    }

    static func formattedClockDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    static func relativeTime(from date: Date, to reference: Date = AppEnvironment.now) -> String {
        Formatters.relativeTime.localizedString(for: date, relativeTo: reference)
    }

    static func nextDate(for weekday: Weekday, from date: Date = AppEnvironment.now, calendar: Calendar = .current) -> Date {
        let targetWeekday = calendarWeekday(for: weekday)
        if calendar.component(.weekday, from: date) == targetWeekday {
            return date
        }
        let components = DateComponents(weekday: targetWeekday)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) ?? date
    }

    private static func calendarWeekday(for weekday: Weekday) -> Int {
        switch weekday {
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
