import Foundation

/// Calendar and session-boundary recognition for handwritten workout text.
/// Kept separate from exercise/set parsing so date rules remain independently
/// understandable and deterministic.
nonisolated enum HandwrittenWorkoutDateParser {
    struct Match {
        var date: Date
        var range: Range<String.Index>
    }

    static func explicitDate(in text: String, referenceDate: Date) -> Date? {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            if let match = detectDate(in: String(line), referenceDate: referenceDate) {
                return match.date
            }
        }
        return nil
    }

    static func isSessionDateHeader(_ rawLine: String, referenceDate: Date) -> Bool {
        let line = HandwrittenWorkoutText.normalize(rawLine)
        guard !line.isEmpty else { return false }

        var remainder = line
        var foundDate = false
        if let relative = detectRelativeDate(in: remainder, referenceDate: referenceDate) {
            foundDate = true
            remainder = HandwrittenWorkoutText.normalize(
                remainder.replacingCharacters(in: relative.range, with: " ")
            )
        }
        if let match = detectDate(in: remainder, referenceDate: referenceDate) {
            foundDate = true
            remainder = HandwrittenWorkoutText.normalize(
                remainder.replacingCharacters(in: match.range, with: " ")
            )
        }
        guard foundDate else { return false }
        remainder = remainder.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        )
        if remainder.isEmpty { return true }
        if HandwrittenWorkoutText.isWeekday(remainder) { return true }
        return HandwrittenWorkoutText.isWordOnly(remainder)
    }

    static func isSessionSplitHeader(_ rawLine: String, referenceDate: Date) -> Bool {
        if isSessionDateHeader(rawLine, referenceDate: referenceDate) { return true }
        return isNumberedSessionHeader(rawLine)
    }

    static func isNumberedSessionHeader(_ rawLine: String) -> Bool {
        numberedSessionHeaderRemainder(rawLine) != nil
    }

    static func numberedSessionHeaderRemainder(_ rawLine: String) -> String? {
        let line = HandwrittenWorkoutText.normalize(rawLine)
        guard !line.isEmpty, let regex = numberedSessionHeaderRegex else { return nil }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange) else { return nil }
        guard match.range(at: 3).location != NSNotFound,
              let remainderRange = Range(match.range(at: 3), in: line) else {
            return ""
        }
        let remainder = line[remainderRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty { return "" }
        guard HandwrittenWorkoutText.isWordOnly(remainder) else { return nil }
        return remainder
    }

    static func detectRelativeDate(in line: String, referenceDate: Date) -> Match? {
        guard let regex = relativeDateRegex,
              let match = firstMatch(regex, in: line),
              let range = Range(match.range, in: line) else { return nil }
        let word = line[range].lowercased()
        let offset: Int
        if word == "yesterday" || word == "last night" {
            offset = -1
        } else if let weekday = weekdayNumber(word) {
            offset = daysBack(toWeekday: weekday, from: referenceDate)
        } else {
            offset = 0
        }
        guard let shifted = Calendar.current.date(byAdding: .day, value: offset, to: referenceDate) else {
            return nil
        }
        return Match(date: shifted, range: range)
    }

    static func detectDate(in line: String, referenceDate: Date) -> Match? {
        if let iso = isoDateRegex, let match = firstMatch(iso, in: line),
           let year = intGroup(match, 1, line),
           let month = intGroup(match, 2, line),
           let day = intGroup(match, 3, line),
           let date = makeDate(year: year, month: month, day: day),
           let range = Range(match.range, in: line) {
            return Match(date: date, range: range)
        }
        if let slash = slashDateRegex, let match = firstMatch(slash, in: line),
           let month = intGroup(match, 1, line), let day = intGroup(match, 2, line) {
            let referenceYear = calendar.component(.year, from: referenceDate)
            let year: Int
            if let raw = intGroup(match, 3, line) {
                year = raw < 100 ? 2000 + raw : raw
            } else {
                year = referenceYear
            }
            guard (1...12).contains(month), (1...31).contains(day),
                  let date = makeDate(year: year, month: month, day: day),
                  let range = Range(match.range, in: line) else { return nil }
            return Match(date: date, range: range)
        }
        return detectMonthNameDate(in: line, referenceDate: referenceDate)
    }

    private static let slashDateRegex = try? NSRegularExpression(
        pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b(?!/\d)"#
    )
    private static let isoDateRegex = try? NSRegularExpression(
        pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#
    )
    private static let relativeDateRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(yesterday|last night|this morning|tonight|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun)\b"#
    )
    private static let numberedSessionHeaderRegex = try? NSRegularExpression(
        pattern: #"^(?i)(day|session|workout)\s+(\d{1,2})(?:\s*[:.\-]\s*(.*))?$"#
    )
    private static let monthNameRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec|may)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{2,4}))?\b"#
    )
    private static let dayMonthNameRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec|may)(?:,?\s+(\d{2,4}))?\b"#
    )

    private static func weekdayNumber(_ word: String) -> Int? {
        switch word {
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue", "tues": return 3
        case "wednesday", "wed", "weds": return 4
        case "thursday", "thu", "thur", "thurs": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return nil
        }
    }

    private static func daysBack(toWeekday weekday: Int, from referenceDate: Date) -> Int {
        let current = Calendar.current.component(.weekday, from: referenceDate)
        return -((current - weekday + 7) % 7)
    }

    private static func detectMonthNameDate(in line: String, referenceDate: Date) -> Match? {
        if let regex = monthNameRegex, let match = firstMatch(regex, in: line),
           let month = monthNumber(group(match, 1, line)),
           let day = intGroup(match, 2, line) {
            return monthDate(
                yearRaw: intGroup(match, 3, line), month: month, day: day,
                range: Range(match.range, in: line), referenceDate: referenceDate
            )
        }
        if let regex = dayMonthNameRegex, let match = firstMatch(regex, in: line),
           let day = intGroup(match, 1, line),
           let month = monthNumber(group(match, 2, line)) {
            return monthDate(
                yearRaw: intGroup(match, 3, line), month: month, day: day,
                range: Range(match.range, in: line), referenceDate: referenceDate
            )
        }
        return nil
    }

    private static func monthDate(
        yearRaw: Int?,
        month: Int,
        day: Int,
        range: Range<String.Index>?,
        referenceDate: Date
    ) -> Match? {
        guard (1...12).contains(month), (1...31).contains(day), let range else { return nil }
        let referenceYear = calendar.component(.year, from: referenceDate)
        let year: Int
        if let raw = yearRaw {
            year = raw < 100 ? 2000 + raw : raw
        } else {
            year = referenceYear
        }
        guard var date = makeDate(year: year, month: month, day: day) else { return nil }
        if yearRaw == nil, date > referenceDate.addingTimeInterval(86_400) {
            date = makeDate(year: year - 1, month: month, day: day) ?? date
        }
        return Match(date: date, range: range)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, _ line: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: line) else { return nil }
        return String(line[range])
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, _ line: String) -> Int? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: line) else { return nil }
        return Int(line[range])
    }

    private static func monthNumber(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "january", "jan": return 1
        case "february", "feb": return 2
        case "march", "mar": return 3
        case "april", "apr": return 4
        case "may": return 5
        case "june", "jun": return 6
        case "july", "jul": return 7
        case "august", "aug": return 8
        case "september", "sept", "sep": return 9
        case "october", "oct": return 10
        case "november", "nov": return 11
        case "december", "dec": return 12
        default: return nil
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}
