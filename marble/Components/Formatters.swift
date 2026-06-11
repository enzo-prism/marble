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
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Pace as runners read it: "4:32 /km" or "7:18 /mi", derived from the
    /// entry's own distance unit. Returns nil when pace is undefined.
    static func paceText(distance: Double, unit: DistanceUnit, durationSeconds: Int) -> String? {
        guard distance > 0, durationSeconds > 0 else { return nil }
        let referenceUnit = unit.paceReferenceUnit
        let referenceDistance = unit.meters(from: distance) / referenceUnit.metersPerUnit
        guard referenceDistance > 0 else { return nil }
        let secondsPerReference = Double(durationSeconds) / referenceDistance
        let rounded = Int(secondsPerReference.rounded())
        let minutes = rounded / 60
        let seconds = rounded % 60
        return String(format: "%d:%02d /%@", minutes, seconds, referenceUnit.symbol)
    }

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
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60

        if hours > 0 {
            var parts = ["\(hours)h"]
            if minutes > 0 {
                parts.append("\(minutes)m")
            }
            if remaining > 0 {
                parts.append("\(remaining)s")
            }
            return parts.joined(separator: " ")
        }
        if minutes == 0 {
            return "\(remaining)s"
        }
        if remaining == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remaining)s"
    }

    static func formattedClockDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }

    static func relativeTime(from date: Date, to reference: Date = AppEnvironment.now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: reference)
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
