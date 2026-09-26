import Foundation

/// Calendar and session-boundary recognition for handwritten workout text.
/// Kept separate from exercise/set parsing so date rules remain independently
/// understandable and deterministic.
///
/// Date policy (shared by the deterministic parser and the Apple Intelligence
/// path, which resolves the model's `dateText` through `resolveDateText`):
///   • Every resolved date is a day in the user's *local* calendar
///     (`Calendar.current`) carrying the reference's time of day — the same
///     "chosen day + current time" convention as backdating a manual set. A
///     date that names today resolves to the reference instant itself.
///     (Dates used to be pinned to 12:00 UTC: 5 AM in California, and the
///     *next* day from UTC+12 eastward.)
///   • A date written without a year is its most recent occurrence on or
///     before today, so "12/30" pasted on Jan 2 is last December, never a
///     future workout.
///   • Slash dates are ambiguous with rep notation, so a slash date is a date
///     ("3/5", "Push 3/5", "Legs 9/21", "Day 3 7/22", "Push 9/21 @ 6am")
///     unless the line marks it as notation: sets/weight notation
///     ("135x10/10/10", "12/10/10 @ 25"), a unit after it ("3/4 mile"), or a
///     2-digit "year" years back ("10/10/10"). After a movement name a
///     year-less pair is a date only when it rises: "Bench 9/21" titles a
///     workout, while "Pull-ups 10/8" and "Dips 12/12" are reps.
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

    /// Resolves a free-form date phrase — the model's `dateText`, e.g. "7/22",
    /// "Monday", "last Tuesday", "2 days ago", "yesterday" — with the same rules
    /// as the deterministic parser. An explicit date beats a weekday in the
    /// same phrase ("Monday 7/22"). Unknown phrases return nil.
    static func resolveDateText(_ text: String, referenceDate: Date) -> Date? {
        let cleaned = text
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
            .lowercased()
        guard !cleaned.isEmpty else { return nil }
        if let timestamp = isoTimestamp(text) { return timestamp }
        if let match = detectDate(in: cleaned, referenceDate: referenceDate) {
            return match.date
        }
        if let days = daysAgo(in: cleaned) {
            return Calendar.current.date(byAdding: .day, value: -days, to: referenceDate)
        }
        return detectRelativeDate(in: cleaned, referenceDate: referenceDate)?.date
    }

    static func isSessionDateHeader(_ rawLine: String, referenceDate: Date) -> Bool {
        let line = HandwrittenWorkoutText.normalize(rawLine)
        guard !line.isEmpty else { return false }

        var remainder = line
        var foundExplicitDate = false
        if let match = detectDate(in: remainder, referenceDate: referenceDate) {
            foundExplicitDate = true
            remainder = HandwrittenWorkoutText.normalize(
                remainder.replacingCharacters(in: match.range, with: " ")
            )
        }
        var foundRelativeDate = false
        if let relative = detectLeadingRelativeDate(in: remainder, referenceDate: referenceDate) {
            foundRelativeDate = true
            remainder = HandwrittenWorkoutText.normalize(
                remainder.replacingCharacters(in: relative.range, with: " ")
            )
        }
        guard foundExplicitDate || foundRelativeDate else { return false }
        // "Push 9/21 @ 6am" / "Legs 9/21 @ gym": a when/where note, not a load.
        remainder = remainder.replacingOccurrences(
            of: #"(?i)\s*@\s*(\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2}|[a-z][a-z' ]*)$"#,
            with: "",
            options: .regularExpression
        )
        remainder = remainder.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        )
        if remainder.isEmpty { return true }

        // Relative words are common in ordinary notes ("Felt strong today"),
        // so only a leading relative date can introduce a boundary. A leading
        // weekday/date may still carry a word-only workout title, preserving
        // inputs such as "Monday — Push" and "Push day 3/5" while rejecting
        // lines that also contain set notation.
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

    /// "today"/"this morning"/"tonight" → the reference instant;
    /// "yesterday"/"last night" → one day earlier at the same clock time; a
    /// weekday → its most recent occurrence (today when it names today), and
    /// "last <weekday>" → strictly before today.
    static func detectRelativeDate(in line: String, referenceDate: Date) -> Match? {
        guard let regex = relativeDateRegex,
              let match = firstMatch(regex, in: line),
              let range = Range(match.range, in: line) else { return nil }
        let phrase = line[range].lowercased()
        let offset: Int
        if phrase == "yesterday" || phrase == "last night" {
            offset = -1
        } else if let weekday = weekdayNumber(weekdayWord(in: phrase)) {
            let back = daysBack(toWeekday: weekday, from: referenceDate)
            offset = (back == 0 && phrase.hasPrefix("last")) ? -7 : back
        } else {
            offset = 0
        }
        guard let shifted = Calendar.current.date(byAdding: .day, value: offset, to: referenceDate) else {
            return nil
        }
        return Match(date: shifted, range: range)
    }

    /// Relative dates describe a workout only when they lead the line. This
    /// keeps prose such as "Felt strong today" intact as a note instead of
    /// changing the workout date or creating a false session boundary. A
    /// word-only title after the date needs a visible separator, which keeps
    /// "Today felt strong" as prose while preserving "Today — Push".
    static func detectLeadingRelativeDate(in line: String, referenceDate: Date) -> Match? {
        guard let match = detectRelativeDate(in: line, referenceDate: referenceDate) else {
            return nil
        }
        let prefix = line[..<match.range.lowerBound].trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        )
        guard prefix.isEmpty else { return nil }

        let suffix = line[match.range.upperBound...].trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !suffix.isEmpty else { return match }
        if let first = suffix.first, relativeTitleSeparators.contains(first) {
            return match
        }
        // Weekday abbreviations are also ordinary words and exercise prefixes
        // ("Sun salutation 3x5", "Sat 3x10 wall sit"): with anything after
        // them they only count when an explicit date follows ("Mon 3/5").
        let word = weekdayWord(in: line[match.range].lowercased())
        if weekdayNumber(word) != nil, !fullWeekdayNames.contains(word) {
            return detectDate(in: String(suffix), referenceDate: referenceDate)
                .map { _ in match }
        }

        return HandwrittenWorkoutText.isWordOnly(String(suffix)) ? nil : match
    }

    static func detectDate(in line: String, referenceDate: Date) -> Match? {
        if let iso = isoDateRegex, let match = firstMatch(iso, in: line),
           let year = intGroup(match, 1, line),
           let month = intGroup(match, 2, line),
           let day = intGroup(match, 3, line),
           let date = makeDate(year: year, month: month, day: day, referenceDate: referenceDate),
           let range = Range(match.range, in: line) {
            return Match(date: date, range: range)
        }
        if let slash = slashDateRegex {
            let nsRange = NSRange(line.startIndex..., in: line)
            for match in slash.matches(in: line, range: nsRange) {
                guard let range = Range(match.range, in: line),
                      let context = slashDateContext(range, in: line),
                      let month = intGroup(match, 1, line),
                      let day = intGroup(match, 2, line),
                      let date = resolvedDate(
                        yearRaw: intGroup(match, 3, line), month: month, day: day,
                        referenceDate: referenceDate
                      ) else { continue }
                let yearRaw = intGroup(match, 3, line)
                // A 2-digit "year" that lands years back is a rep ladder
                // ("10/10/10", "Legs 12/10/10") when nothing or a movement
                // precedes it, or when the three numbers hold or fall —
                // "Push 9/22/19" stays a 2019 date.
                if let yearRaw, yearRaw < 100,
                   context != .date || (month >= day && day >= yearRaw),
                   Calendar.current.dateComponents([.year], from: date, to: referenceDate).year ?? 0 > 5 {
                    continue
                }
                // After a movement name, rep pairs hold or drop ("10/8",
                // "12/10", "12/12") while a workout date there almost always
                // rises ("Bench 9/21", "Squat 9/22"): a year-less pair that
                // doesn't rise is reps.
                if context == .afterMovement, yearRaw == nil, month >= day {
                    continue
                }
                return Match(date: date, range: range)
            }
        }
        return detectMonthNameDate(in: line, referenceDate: referenceDate)
    }

    // MARK: - Slash-date context

    /// Title words that keep a slash date a session date even next to a
    /// movement word ("Bench day 3/5", "Day 3 7/22", "Wk 3 Day 2 7/22").
    private static let dateTitleWords: Set<String> = [
        "day", "workout", "session", "training", "gym", "lift", "lifting", "week", "wk",
    ]
    /// Relative words that make a trailing slash date a date; two-word
    /// phrases are matched joined ("last night" → "lastnight") so a lone
    /// "last" ("Last set bench 10/8") does not count.
    private static let relativeWords: Set<String> = [
        "today", "yesterday", "tonight", "lastnight", "thismorning",
    ]
    /// Whole-word movement names (hyphens removed, so "Pull-ups" is
    /// "pullups"). A slash after one of these is rep notation ("Pull-ups
    /// 10/8", "Dips 12/10"), while split titles ("Push 3/5", "Legs 9/21",
    /// "Pull 9/21", "Upper A 9/22", "Chest & Back 7/22") stay dates.
    private static let movementWords: Set<String> = [
        "bench", "squat", "squats", "deadlift", "deadlifts", "dl", "rdl", "rdls",
        "row", "rows", "press", "ohp", "curl", "curls", "dip", "dips",
        "pullup", "pullups", "pushup", "pushups", "chinup", "chinups", "chins",
        "lunge", "lunges", "plank", "planks", "skullcrusher", "skullcrushers",
        "extension", "extensions", "raise", "raises", "fly", "flys", "flyes",
        "pulldown", "pulldowns", "pushdown", "pushdowns", "shrug", "shrugs",
        "crunch", "crunches", "situp", "situps", "burpee", "burpees",
        "thruster", "thrusters", "snatch", "clean", "cleans", "jerk", "thrust",
        "thrusts", "swing", "swings", "stepup", "stepups", "facepull", "facepulls",
        "carry", "carries", "kickback", "kickbacks", "muscleup", "muscleups",
        "hipthrust", "hipthrusts", "goodmorning", "goodmornings", "farmerswalk",
        "farmerscarry", "pecdeck", "bridge", "bridges", "crossover", "crossovers",
        "jump", "jumps", "wallball", "wallballs", "twist", "twists", "abwheel",
        "rollout", "rollouts", "pistol", "pistols", "hang", "sled", "incline",
        "decline", "db", "bb", "kb", "dumbbell", "barbell", "kettlebell", "cable",
    ]
    /// Units and notation that make "3/4 mile" or "10/8 reps" a quantity.
    private static let quantityFollowers: Set<String> = [
        "x", "mi", "mile", "miles", "km", "k", "m", "meter", "meters", "yd", "yards",
        "lb", "lbs", "kg", "kgs", "rep", "reps", "effort", "bw", "min", "mins", "sec", "secs",
        "hr", "hrs", "hour", "hours",
    ]

    /// `.leading`: nothing before the slash; `.afterMovement`: a movement name
    /// before it ("Bench 9/21" vs "Bench 10/8"); `.date`: anything else.
    private enum SlashDateContext { case leading, date, afterMovement }

    /// A slash date is a date unless the line says it is set notation: a load
    /// right after it ("12/10/10 @ 25"), sets/weight notation before it
    /// ("135x10/10/10"), or a unit after it ("3/4 mile", "1/2 hr"). After a
    /// movement name ("Bench 9/21" vs "Bench 10/8") it is ambiguous, and the
    /// caller decides from the numbers' shape.
    private static func slashDateContext(_ range: Range<String.Index>, in line: String) -> SlashDateContext? {
        let suffix = line[range.upperBound...]
        let followerWord = suffix
            .drop(while: { $0 == " " })
            .prefix(while: { $0.isLetter })
            .lowercased()
        if quantityFollowers.contains(followerWord) { return nil }
        if suffix.first?.isLetter == true { return nil }
        // "@ 25" / "@25kg" right after the slash is a load; "@ 6am" or
        // "@ gym" is where or when the workout happened.
        if String(suffix).range(of: #"^\s*@\s*\d+(\.\d+)?(?!\s*(am|pm|:)|\d)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        let prefix = line[..<range.lowerBound].trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        )
        guard !prefix.isEmpty else { return .leading }
        if containsSetNotation(prefix) { return nil }
        let words = prefix.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { $0.replacingOccurrences(of: "'", with: "") }
        // Two-word names and phrases count joined ("Pull ups" → "pullups").
        let joined = zip(words, words.dropFirst()).map { $0 + $1 }
        if words.contains(where: { dateTitleWords.contains($0) || relativeWords.contains($0) || weekdayNumber($0) != nil })
            || joined.contains(where: relativeWords.contains) {
            return .date
        }
        let isMovement = words.contains(where: movementWords.contains) || joined.contains(where: movementWords.contains)
        return isMovement ? .afterMovement : .date
    }

    /// A load, full sets×reps ("3x8"), or a count attached right before the
    /// slash ("135x" in "135x10/10/10"). A multiplier in a title ("Full Body
    /// x2") is not notation.
    private static func containsSetNotation(_ text: String) -> Bool {
        text.contains("@")
            || text.range(of: #"(?i)\d\s*x\s*\d"#, options: .regularExpression) != nil
            || text.range(of: #"(?i)\d\s*x$"#, options: .regularExpression) != nil
    }

    // MARK: - Resolution

    /// Builds the local day, rolling a year-less date back to its most recent
    /// occurrence on or before the reference day.
    private static func resolvedDate(yearRaw: Int?, month: Int, day: Int, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        guard let yearRaw else {
            let referenceYear = calendar.component(.year, from: referenceDate)
            if let date = makeDate(year: referenceYear, month: month, day: day, referenceDate: referenceDate),
               calendar.startOfDay(for: date) <= calendar.startOfDay(for: referenceDate) {
                return date
            }
            return makeDate(year: referenceYear - 1, month: month, day: day, referenceDate: referenceDate)
        }
        let year: Int
        switch yearRaw {
        case 0..<100: year = 2000 + yearRaw
        case 1000...: year = yearRaw
        default: return nil
        }
        return makeDate(year: year, month: month, day: day, referenceDate: referenceDate)
    }

    /// A real local calendar day (no 2/31 → 3/3 rollover) at the reference's
    /// time of day; the reference instant itself when the day is today.
    private static func makeDate(year: Int, month: Int, day: Int, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let dayStart = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: dayStart)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        if calendar.isDate(dayStart, inSameDayAs: referenceDate) { return referenceDate }
        return DateHelper.merge(day: dayStart, time: referenceDate, calendar: calendar)
    }

    /// A full timestamp keeps its own time: with a zone ("…Z", "…-07:00") it
    /// is that instant; without one it is local wall-clock time.
    private static func isoTimestamp(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}"#, options: .regularExpression) != nil else {
            return nil
        }
        // Formatters roll impossible days over ("02-30" → March 2); refuse them.
        let parts = trimmed.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              DateComponents(year: parts[0], month: parts[1], day: parts[2])
                .isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }
        let zoned = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            zoned.formatOptions = options
            if let date = zoned.date(from: trimmed) { return date }
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.calendar = Calendar(identifier: .gregorian)
        local.timeZone = Calendar.current.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: trimmed) { return date }
        }
        return nil
    }

    private static func daysAgo(in text: String) -> Int? {
        guard let regex = daysAgoRegex, let match = firstMatch(regex, in: text),
              let raw = group(match, 1, text)?.lowercased() else { return nil }
        let words = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7]
        guard let days = Int(raw) ?? words[raw], (0...60).contains(days) else { return nil }
        return days
    }

    private static let slashDateRegex = try? NSRegularExpression(
        pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b(?!/\d)"#
    )
    // `(?!\d)` rather than `\b` so an ISO timestamp ("2026-07-22T18:00")
    // still yields its date.
    private static let isoDateRegex = try? NSRegularExpression(
        pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#
    )
    private static let relativeDateRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(yesterday|last night|this morning|tonight|today|(?:last\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun))\b"#
    )
    private static let daysAgoRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2}|a|one|two|three|four|five|six|seven)\s+days?\s+ago\b"#
    )
    private static let relativeTitleSeparators: Set<Character> = [":", "-", "–", "—", "|", "•"]
    private static let numberedSessionHeaderRegex = try? NSRegularExpression(
        pattern: #"^(?i)(day|session|workout)\s+(\d{1,2})(?:\s*[:.\-]\s*(.*))?$"#
    )
    private static let monthNameRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec|may)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{2,4}))?\b"#
    )
    private static let dayMonthNameRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec|may)(?:,?\s+(\d{2,4}))?\b"#
    )

    private static let fullWeekdayNames: Set<String> = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    /// The weekday token of a relative phrase ("last tues" → "tues").
    private static func weekdayWord(in phrase: String) -> String {
        String(phrase.split(whereSeparator: \.isWhitespace).last ?? "")
    }

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
           let day = intGroup(match, 2, line),
           let range = Range(match.range, in: line),
           let date = resolvedDate(
            yearRaw: intGroup(match, 3, line), month: month, day: day, referenceDate: referenceDate
           ) {
            return Match(date: date, range: range)
        }
        if let regex = dayMonthNameRegex, let match = firstMatch(regex, in: line),
           let day = intGroup(match, 1, line),
           let month = monthNumber(group(match, 2, line)),
           let range = Range(match.range, in: line),
           let date = resolvedDate(
            yearRaw: intGroup(match, 3, line), month: month, day: day, referenceDate: referenceDate
           ) {
            return Match(date: date, range: range)
        }
        return nil
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
}
