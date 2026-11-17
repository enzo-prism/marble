import Foundation

// MARK: - Time phrases

/// Finds time phrases in a question ("this week", "last 30 days", "in
/// October", "2026-11-01 to 2026-11-10"). Deterministic and shared by the
/// fallback matcher and the model's tools, so a period the model mis-states
/// is still read the same way the question wrote it.
nonisolated enum JournalTimeParser {
    struct Match: Equatable {
        let range: Range<String.Index>
        let period: JournalPeriod
    }

    /// The first period in `text`, if any.
    static func period(in text: String, now: Date, calendar: Calendar) -> JournalPeriod? {
        matches(in: text, now: now, calendar: calendar).first?.period
    }

    /// Every non-overlapping time phrase, in reading order.
    static func matches(in text: String, now: Date, calendar: Calendar) -> [Match] {
        let lowered = text.lowercased()
        var found: [Match] = []

        func claim(_ pattern: String, _ build: ([String?]) -> JournalPeriod?) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            let nsRange = NSRange(lowered.startIndex..., in: lowered)
            for result in regex.matches(in: lowered, range: nsRange) {
                guard let range = Range(result.range, in: lowered),
                      !found.contains(where: { $0.range.overlaps(range) }) else { continue }
                let groups: [String?] = (0..<result.numberOfRanges).map { index in
                    Range(result.range(at: index), in: lowered).map { String(lowered[$0]) }
                }
                if let period = build(groups) {
                    found.append(Match(range: range, period: period))
                }
            }
        }

        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        claim(#"(?:from\s+|between\s+)?(\d{4}-\d{1,2}-\d{1,2})\s*(?:to|through|until|and|-|–)\s*(\d{4}-\d{1,2}-\d{1,2})"#) { groups in
            guard let start = isoDay(groups[1], calendar: calendar),
                  let last = isoDay(groups[2], calendar: calendar) else { return nil }
            let lower = min(start, last)
            let upper = max(start, last)
            guard let end = calendar.date(byAdding: .day, value: 1, to: upper) else { return nil }
            return .between(start: lower, end: end)
        }
        claim(#"since\s+(\d{4}-\d{1,2}-\d{1,2})"#) { groups in
            guard let start = isoDay(groups[1], calendar: calendar) else { return nil }
            return .between(start: start, end: max(tomorrow, calendar.date(byAdding: .day, value: 1, to: start) ?? tomorrow))
        }
        claim(#"(?:on\s+)?(\d{4}-\d{1,2}-\d{1,2})"#) { groups in
            guard let day = isoDay(groups[1], calendar: calendar),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return .between(start: day, end: end)
        }
        // "since October", "since Oct 5", "since October 5, 2025": open-ended
        // from that day (the most recent one not in the future) through today.
        claim(#"since\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\b(?:\s+(\d{1,2})(?:st|nd|rd|th)?\b)?(?:,?\s+((?:19|20)\d{2}))?"#) { groups in
            guard let name = groups[1], let month = monthNumber(name) else { return nil }
            let day = groups[2].flatMap { Int($0) } ?? 1
            let current = calendar.dateComponents([.year], from: now)
            var year = groups[3].flatMap { Int($0) } ?? current.year ?? 2000
            guard var start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: start) == day else { return nil }
            if groups[3] == nil, start > now {
                year -= 1
                guard let previous = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
                start = previous
            }
            start = calendar.startOfDay(for: start)
            return .between(start: start, end: max(tomorrow, calendar.date(byAdding: .day, value: 1, to: start) ?? tomorrow))
        }
        claim(#"since\s+((?:19|20)\d{2})\b"#) { groups in
            guard let year = groups[1].flatMap({ Int($0) }),
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return .between(start: start, end: max(tomorrow, calendar.date(byAdding: .day, value: 1, to: start) ?? tomorrow))
        }
        claim(#"(?:(?:in|over|during|for)\s+)?(?:the\s+)?(?:last|past|previous)\s+(\d{1,3})\s+(days?|weeks?|months?)\b"#) { groups in
            guard let count = groups[1].flatMap({ Int($0) }), count > 0, let unit = groups[2] else { return nil }
            if unit.hasPrefix("day") { return .lastDays(count) }
            if unit.hasPrefix("week") { return .lastDays(count * 7) }
            return .lastMonths(count)
        }
        claim(#"\b(?:this|current)\s+(week|month|year)\b"#) { groups in
            switch groups[1] {
            case "week": return .thisWeek
            case "month": return .thisMonth
            default: return .thisYear
            }
        }
        claim(#"\b(?:last|previous)\s+(week|month|year)\b"#) { groups in
            switch groups[1] {
            case "week": return .lastWeek
            case "month": return .lastMonth
            default: return .lastYear
            }
        }
        claim(#"\b(?:in\s+|over\s+|during\s+)?(?:the\s+)?past\s+(week|month|year)\b"#) { groups in
            switch groups[1] {
            case "week": return .lastDays(7)
            case "month": return .lastDays(30)
            default: return .lastDays(365)
            }
        }
        claim(#"\b(today|tonight|this morning)\b"#) { _ in .today }
        claim(#"\byesterday\b"#) { _ in .yesterday }
        claim(#"\b(?:of\s+)?all[\s-]time\b|\bever\b"#) { _ in .allTime }
        // "May" is an ordinary word too; only read it as a month after a preposition.
        claim(#"\b(?:(in|during|of|for)\s+)?(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\b(?:\s+(\d{4}))?"#) { groups in
            guard let name = groups[2], let month = monthNumber(name) else { return nil }
            if name == "may", groups[1] == nil, groups[3] == nil { return nil }
            let current = calendar.dateComponents([.year, .month], from: now)
            var year = groups[3].flatMap { Int($0) } ?? current.year ?? 2000
            if groups[3] == nil, let currentMonth = current.month, month > currentMonth { year -= 1 }
            return .month(year: year, month: month)
        }

        // A whole year: "in 2025", "during 2024", or a bare year that isn't a
        // load ("2025" — never "2025 lb").
        claim(#"(?<![\d\-/.])\b(?:(?:in|during|for|of)\s+)?((?:19|20)\d{2})\b(?![.,\-/]\d)(?!\s*(?:lbs?|pounds?|kgs?|kilos?|kilograms?|m|km|mi|yd|meters?|metres?|miles?|yards?|reps?|sets?|x)\b)"#) { groups in
            groups[1].flatMap { Int($0) }.map { JournalPeriod.year($0) }
        }

        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func isoDay(_ text: String?, calendar: Calendar) -> Date? {
        guard let parts = text?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3,
              (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        // Reject rollovers like 2026-02-31.
        guard calendar.component(.day, from: date) == parts[2] else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func monthNumber(_ name: String) -> Int? {
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return prefixes.firstIndex(where: { name.hasPrefix($0) }).map { $0 + 1 }
    }
}

// MARK: - Question parsing

/// What a question says, read deterministically: its time phrases, the
/// library exercise it names, a weight threshold, a sprint distance and its
/// intent cues. The fallback matcher turns this into a `JournalQuery`; the
/// model's tools use it as the authority for anything the question states.
nonisolated struct JournalQuestionReading: Equatable, Sendable {
    var periods: [JournalPeriod] = []
    var exercise: ExerciseMatcher.Candidate?
    var threshold: WeightThreshold?
    var distanceMeters: Double?
    /// Words left after removing time phrases, numbers and question words —
    /// used as a workout-title search ("leg day").
    var leftoverTerm: String = ""
    var tokens: [String] = []

    /// The single period the question states, nil when it states none or
    /// several (a comparison the model should resolve itself).
    var solePeriod: JournalPeriod? { periods.count == 1 ? periods[0] : nil }
}

/// Maps a free-text question onto the deterministic engine without the
/// model: keyword intents ("last", "best/heaviest/PR", "how many"), a library
/// exercise found through `ExerciseMatcher`, and time phrases. Returns nil
/// when nothing it understands is asked, so the sheet can say what Marble can
/// answer instead of guessing.
nonisolated struct JournalQuestionMatcher {
    /// Library exercises, most recently logged first (ties prefer recent use).
    let library: [ExerciseMatcher.Candidate]
    let preferredUnit: WeightUnit
    let now: Date
    let calendar: Calendar

    static let questionWords: Set<String> = [
        "i", "me", "my", "mine", "the", "a", "an", "was", "is", "were", "are", "did", "do", "does",
        "have", "has", "had", "when", "what", "whats", "s", "how", "many", "much", "show", "list",
        "tell", "about", "can", "you", "it", "that", "this", "which", "go", "went", "get", "got",
        "done", "doing", "on", "at", "in", "for", "of", "to", "with", "and", "or", "ever", "time",
        "times", "last", "latest", "recent", "recently", "most", "previous", "again", "please",
        "ago", "workout", "workouts", "session", "sessions", "training", "trained", "train",
        "set", "sets", "rep", "reps", "lift", "lifted", "lifting", "lifts", "log", "logged",
        "best", "heaviest", "max", "maximum", "pr", "prs", "personal", "record", "records",
        "fastest", "quickest", "longest", "strongest", "top", "heavy", "volume", "total", "totals",
        "count", "number", "lb", "lbs", "pound", "pounds", "kg", "kgs", "kilo", "kilos", "kilogram",
        "kilograms", "more", "over", "above", "least", "plus", "m", "meter", "meters", "metre",
        "metres", "km", "mi", "mile", "miles", "yd", "yard", "yards", "than", "so", "far", "all",
        "there", "been", "be", "any", "today", "week", "month", "year", "days", "weeks", "months",
        "perform", "performed", "hit", "moved", "own", "journal", "marble", "since", "from", "then"
    ]

    private static let totalsCues = ["how many", "how much", "total", "volume", "count", "number of", "tally"]
    private static let bestTokens: Set<String> = [
        "best", "heaviest", "max", "maximum", "pr", "prs", "record", "records", "fastest", "quickest",
        "longest", "strongest", "top", "biggest"
    ]
    private static let lastTokens: Set<String> = ["last", "latest", "recent", "recently", "previous", "when"]
    private static let listCues = ["what did i", "what have i", "show", "list", "which workouts", "workouts", "sessions", "what workouts"]
    private static let sessionTokens: Set<String> = ["workout", "workouts", "session", "sessions", "training"]

    func reading(of question: String) -> JournalQuestionReading {
        var reading = JournalQuestionReading()
        let lowered = question.lowercased()
        let timeMatches = JournalTimeParser.matches(in: lowered, now: now, calendar: calendar)
        reading.periods = timeMatches.map(\.period)

        var remainder = lowered
        for match in timeMatches.reversed() {
            remainder.replaceSubrange(match.range, with: " ")
        }

        reading.threshold = Self.threshold(in: remainder, preferredUnit: preferredUnit)
        reading.distanceMeters = Self.distanceMeters(in: remainder)

        let tokens = Self.tokens(remainder)
        reading.tokens = tokens
        reading.exercise = exerciseMention(in: tokens)

        let exerciseTokens = Set(reading.exercise.map { Self.tokens($0.name.lowercased()) } ?? [])
        reading.leftoverTerm = tokens
            .filter { !Self.questionWords.contains($0) && !exerciseTokens.contains($0) && Int($0) == nil }
            .filter { $0 != "day" || tokens.count > 1 }
            .joined(separator: " ")
        if reading.leftoverTerm == "day" { reading.leftoverTerm = "" }
        return reading
    }

    /// The deterministic query for `question`, or nil when nothing matched.
    func query(for question: String) -> JournalQuery? {
        let reading = reading(of: question)
        let lowered = " " + Self.tokens(question.lowercased()).joined(separator: " ") + " "
        let tokenSet = Set(reading.tokens)
        let period = reading.periods.first

        if Self.totalsCues.contains(where: { lowered.contains(" \($0) ") }) {
            return .totals(period: period ?? .allTime, exerciseID: reading.exercise?.id)
        }

        let wantsBest = !tokenSet.isDisjoint(with: Self.bestTokens) || lowered.contains(" most reps ")
        if wantsBest {
            guard let exercise = reading.exercise else { return nil }
            return .best(
                exerciseID: exercise.id,
                measure: Self.measure(tokens: tokenSet, lowered: lowered),
                period: period ?? .allTime,
                distanceMeters: reading.distanceMeters
            )
        }

        if !tokenSet.isDisjoint(with: Self.lastTokens) {
            if let exercise = reading.exercise {
                return .lastPerformed(exerciseID: exercise.id, atLeast: reading.threshold)
            }
            if period != nil, !tokenSet.contains("when") {
                return .sessions(period: period ?? .allTime)
            }
            return .recentSession(matching: reading.leftoverTerm)
        }

        if let period {
            if let exercise = reading.exercise {
                return .totals(period: period, exerciseID: exercise.id)
            }
            return .sessions(period: period)
        }

        if let exercise = reading.exercise {
            return .lastPerformed(exerciseID: exercise.id, atLeast: reading.threshold)
        }

        if Self.listCues.contains(where: { lowered.contains(" \($0) ") }) || !tokenSet.isDisjoint(with: Self.sessionTokens) {
            return .sessions(period: .allTime)
        }
        return nil
    }

    // MARK: - Pieces

    private static func measure(tokens: Set<String>, lowered: String) -> JournalBestMeasure {
        if tokens.contains("fastest") || tokens.contains("quickest") { return .fastest }
        if tokens.contains("longest") { return .longest }
        if lowered.contains(" most reps ") || (tokens.contains("most") && tokens.contains("reps")) { return .mostReps }
        if tokens.contains("heaviest") || tokens.contains("strongest") || tokens.contains("biggest") { return .heaviest }
        return .automatic
    }

    /// "185 lb", "100kg", "at 185" (the preferred unit).
    static func threshold(in text: String, preferredUnit: WeightUnit) -> WeightThreshold? {
        let lowered = text.lowercased()
        if let groups = firstMatch(#"(\d+(?:\.\d+)?)\s*(lbs?|pounds?|kgs?|kilos?|kilograms?)\b"#, in: lowered),
           let value = groups[1].flatMap(Double.init), value > 0 {
            let unit: WeightUnit = (groups[2] ?? "").hasPrefix("k") ? .kg : .lb
            return WeightThreshold(value: value, unit: unit)
        }
        // Unit-less numbers: "at 185", or a bare load ("last time I benched
        // 185") that isn't a count of reps/sets, a distance, a duration — or
        // a year (1900–2100 is always read as a date, never a load).
        let unitless = [
            #"\b(?:at|over|above|with|least|of)\s+(\d+(?:\.\d+)?)\b(?!\s*(?:m|km|mi|yd|meters?|metres?|miles?|yards?|reps?|sets?)\b)"#,
            #"(?<![\d.])(\d{2,4}(?:\.\d+)?)\b(?!\s*(?:x|m|km|mi|yd|meters?|metres?|miles?|yards?|reps?|sets?|times|s|sec|seconds?|min|minutes?)\b)"#
        ]
        for pattern in unitless {
            for groups in allMatches(pattern, in: lowered) {
                guard let value = groups[1].flatMap(Double.init), value >= 10, !isYear(value) else { continue }
                return WeightThreshold(value: value, unit: preferredUnit)
            }
        }
        return nil
    }

    /// "100m", "60 meters", "1 mile" → meters.
    static func distanceMeters(in text: String) -> Double? {
        guard let groups = firstMatch(#"(\d+(?:\.\d+)?)\s*(m|meters?|metres?|yd|yds|yards?|km|kilometers?|kilometres?|mi|miles?)\b"#, in: text.lowercased()),
              let value = groups[1].flatMap(Double.init), value > 0, let unitText = groups[2] else { return nil }
        let unit: DistanceUnit
        if unitText.hasPrefix("k") { unit = .kilometers }
        else if unitText.hasPrefix("mi") { unit = .miles }
        else if unitText.hasPrefix("y") { unit = .yards }
        else { unit = .meters }
        return unit.meters(from: value)
    }

    static func isYear(_ value: Double) -> Bool {
        value == value.rounded() && (1900...2100).contains(value)
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (0..<result.numberOfRanges).map { index in
                Range(result.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    /// Lowercased word tokens with light verb folding ("benched" → "bench",
    /// "squatting" → "squat", "ran" → "run").
    static func tokens(_ text: String) -> [String] {
        let cleaned = String(text.lowercased().map { ($0.isLetter || $0.isNumber || $0 == ".") ? $0 : " " })
        return cleaned.split(separator: " ").map { token in
            var word = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let irregular = irregularVerbs[word] { return irregular }
            for suffix in ["ing", "ed"] where word.count > suffix.count + 3 && word.hasSuffix(suffix) {
                word = String(word.dropLast(suffix.count))
                if let last = word.last, word.dropLast().last == last, !"slz".contains(last) {
                    word = String(word.dropLast())
                }
                break
            }
            return word
        }.filter { !$0.isEmpty }
    }

    private static let irregularVerbs = ["ran": "run", "swam": "swim", "rode": "ride"]

    /// The library exercise the question names, found by scoring every run
    /// of up to four non-question words with `ExerciseMatcher`. Confidence,
    /// then score, then phrase length decide; equal candidates prefer the
    /// most recently logged exercise.
    private func exerciseMention(in tokens: [String]) -> ExerciseMatcher.Candidate? {
        guard !library.isEmpty else { return nil }
        let matcher = ExerciseMatcher(candidates: library)
        let order = Dictionary(library.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        var runs: [[String]] = [[]]
        for token in tokens {
            if Self.questionWords.contains(token) || Double(token) != nil {
                if !(runs.last?.isEmpty ?? true) { runs.append([]) }
            } else {
                runs[runs.count - 1].append(token)
            }
        }

        var best: (match: ExerciseMatcher.Match, length: Int)?
        for run in runs where !run.isEmpty {
            for length in stride(from: min(4, run.count), through: 1, by: -1) {
                for start in 0...(run.count - length) {
                    let phrase = run[start..<(start + length)].joined(separator: " ")
                    let ranked = matcher.topMatches(for: phrase, limit: 8)
                    guard let top = ranked.first else { continue }
                    let tied = ranked.filter { $0.score == top.score && $0.confidence == top.confidence }
                    let chosen = tied.min { (order[$0.candidate.id] ?? .max) < (order[$1.candidate.id] ?? .max) } ?? top
                    if let current = best {
                        if Self.isBetter(chosen, length: length, than: current.match, length: current.length) {
                            best = (chosen, length)
                        }
                    } else {
                        best = (chosen, length)
                    }
                }
            }
        }
        return best?.match.candidate
    }

    private static func isBetter(_ lhs: ExerciseMatcher.Match, length lhsLength: Int, than rhs: ExerciseMatcher.Match, length rhsLength: Int) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhsLength > rhsLength
    }
}

