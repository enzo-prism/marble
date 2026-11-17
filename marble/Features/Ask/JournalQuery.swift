import Foundation

// MARK: - Periods

/// A span of the journal a question is about ("this week", "last 30 days",
/// "in October", "2026-11-01 to 2026-11-10"). Pure value; resolved against an
/// explicit `now` and calendar so tests and the model path agree exactly.
nonisolated enum JournalPeriod: Equatable, Hashable, Sendable {
    case allTime
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear
    /// The trailing `n` calendar days, today included.
    case lastDays(Int)
    /// The trailing `n` calendar months up to the end of today.
    case lastMonths(Int)
    case month(year: Int, month: Int)
    /// A whole calendar year ("in 2025").
    case year(Int)
    /// Day-aligned `[start, end)`; `end` is exclusive.
    case between(start: Date, end: Date)

    /// The half-open interval to query, nil for all time.
    func interval(now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .allTime:
            return nil
        case .today:
            return DateInterval(start: today, end: tomorrow)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .lastWeek:
            guard let current = calendar.dateInterval(of: .weekOfYear, for: now),
                  let previous = calendar.date(byAdding: .day, value: -1, to: current.start) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: previous)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            guard let current = calendar.dateInterval(of: .month, for: now),
                  let previous = calendar.date(byAdding: .day, value: -1, to: current.start) else { return nil }
            return calendar.dateInterval(of: .month, for: previous)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .lastYear:
            guard let current = calendar.dateInterval(of: .year, for: now),
                  let previous = calendar.date(byAdding: .day, value: -1, to: current.start) else { return nil }
            return calendar.dateInterval(of: .year, for: previous)
        case .lastDays(let days):
            let count = max(1, days)
            let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .lastMonths(let months):
            let start = calendar.date(byAdding: .month, value: -max(1, months), to: tomorrow) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .month(let year, let month):
            guard let anchor = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return calendar.dateInterval(of: .month, for: anchor)
        case .year(let year):
            guard let anchor = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.dateInterval(of: .year, for: anchor)
        case .between(let start, let end):
            guard end > start else { return DateInterval(start: start, end: start) }
            return DateInterval(start: start, end: end)
        }
    }

    /// Words for the period that read after a statement ("… this week",
    /// "… in the last 30 days", "… from Nov 1, 2026 to Nov 10, 2026").
    func label(calendar: Calendar) -> String {
        switch self {
        case .allTime: return "all time"
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .thisWeek: return "this week"
        case .lastWeek: return "last week"
        case .thisMonth: return "this month"
        case .lastMonth: return "last month"
        case .thisYear: return "this year"
        case .lastYear: return "last year"
        case .lastDays(let days): return days <= 1 ? "today" : "in the last \(days) days"
        case .lastMonths(let months): return months <= 1 ? "in the last month" : "in the last \(months) months"
        case .month(let year, let month):
            let names = AskFormat.monthNames
            let name = (1...12).contains(month) ? names[month - 1] : "month \(month)"
            return "in \(name) \(year)"
        case .year(let year):
            return "in \(year)"
        case .between(let start, let end):
            let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
            if calendar.isDate(start, inSameDayAs: lastDay) || lastDay < start {
                return "on \(AskFormat.date(start, calendar: calendar))"
            }
            return "from \(AskFormat.date(start, calendar: calendar)) to \(AskFormat.date(lastDay, calendar: calendar))"
        }
    }
}

// MARK: - Queries

nonisolated enum JournalBestMeasure: String, Equatable, Hashable, Sendable, CaseIterable {
    case heaviest
    case mostReps
    case fastest
    case longest
    /// Let the exercise's metrics decide: weight → heaviest, reps → most
    /// reps, distance + time → fastest, time only → longest.
    case automatic
}

/// "At or above 185 lb" for last-time questions, compared in kilograms so a
/// pound threshold finds kilogram-logged sets and vice versa.
nonisolated struct WeightThreshold: Equatable, Hashable, Sendable {
    let value: Double
    let unit: WeightUnit

    var kilograms: Double { PersonalRecords.kilograms(value, unit: unit) }
}

/// Everything the deterministic engine can answer. The fallback matcher and
/// the model's tools both reduce a question to one of these.
nonisolated enum JournalQuery: Equatable, Hashable, Sendable {
    case lastPerformed(exerciseID: UUID, atLeast: WeightThreshold?)
    case best(exerciseID: UUID, measure: JournalBestMeasure, period: JournalPeriod, distanceMeters: Double?)
    case totals(period: JournalPeriod, exerciseID: UUID?)
    /// Most recent completed workout whose title or exercises match `matching`
    /// (empty matches any workout).
    case recentSession(matching: String)
    case sessions(period: JournalPeriod)
}

// MARK: - Results

/// One verifiable fact rendered under the answer. Built only from engine
/// output — never from model text — so what the reader can tap is always
/// what the journal holds.
nonisolated struct JournalCard: Equatable, Hashable, Sendable, Identifiable {
    nonisolated enum Destination: Equatable, Hashable, Sendable {
        case session(UUID)
        case exercise(UUID)
    }

    let id: String
    /// Small uppercase label: "Heaviest set", "Last time", "This week".
    let label: String
    let title: String
    let value: String
    let detail: String
    let destination: Destination?

    var accessibilityText: String {
        [label, title, value, detail].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

nonisolated struct JournalResult: Equatable, Sendable {
    /// Plain-text fact lines. These are the tool output the model reads, and
    /// the grounding set the validator checks its numbers against.
    let facts: [String]
    /// The deterministic sentence shown when the model doesn't phrase it.
    let sentence: String
    let cards: [JournalCard]
    /// False when the journal held nothing matching (the sentence says so).
    let found: Bool

    var factText: String { facts.joined(separator: "\n") }
}

// MARK: - Formatting

/// Fixed-locale formatting shared by facts, template sentences and cards, so
/// the sentence, the cards and the validator always see the same digits.
nonisolated enum AskFormat {
    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    private static let shortMonthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    /// "Nov 3, 2026" in the given calendar's time zone, without any locale
    /// dependency.
    static func date(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              (1...12).contains(month) else { return "" }
        return "\(shortMonthNames[month - 1]) \(day), \(year)"
    }

    /// "today", "yesterday", "12 days ago" — relative to `now` in whole days.
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<0: return "upcoming"
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// Up to `maximumFractionDigits` decimals, trailing zeros dropped, comma
    /// grouping from 10,000 ("41,250").
    static func number(_ value: Double, maximumFractionDigits: Int = 1) -> String {
        let factor = pow(10, Double(maximumFractionDigits))
        let rounded = (value * factor).rounded() / factor
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = abs(rounded) >= 10_000
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// A stored weight shown in the lifter's preferred unit. Same-unit values
    /// keep their logged precision (two decimals); converted values round to
    /// one decimal and carry the logged original for verification.
    static func weight(
        stored: Double,
        loggedUnit: WeightUnit,
        preferred: WeightUnit,
        style: ResistanceTrackingStyle
    ) -> (display: String, value: Double, logged: String?) {
        let converted: Double
        let digits: Int
        if loggedUnit == preferred {
            converted = stored
            digits = 2
        } else {
            converted = LifterAnalytics.displayWeight(
                fromKilograms: PersonalRecords.kilograms(stored, unit: loggedUnit),
                in: preferred
            )
            digits = 1
        }
        let display: String
        let loggedText: String
        switch style {
        case .totalLoad:
            display = "\(number(converted, maximumFractionDigits: digits)) \(preferred.symbol)"
            loggedText = "\(number(stored, maximumFractionDigits: 2)) \(loggedUnit.symbol)"
        case .singleDumbbellPair:
            display = "\(number(converted / 2, maximumFractionDigits: digits)) \(preferred.symbol) each"
            loggedText = "\(number(stored / 2, maximumFractionDigits: 2)) \(loggedUnit.symbol) each"
        }
        return (display, converted, loggedUnit == preferred ? nil : loggedText)
    }

    /// Sprint/run times use the tenths canon ("14.8s", "1:02.4"); untimed
    /// holds read as durations ("2m 30s").
    static func time(tenths: Int, hasDistance: Bool) -> String {
        if hasDistance || tenths % 10 != 0 {
            return SprintTiming.text(tenths: tenths)
        }
        return DateHelper.formattedDuration(seconds: tenths / 10)
    }
}
