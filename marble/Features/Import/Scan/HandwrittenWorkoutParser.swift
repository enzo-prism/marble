import Foundation

/// Turns OCR / model text into structured workout data for review.
///
/// Conformers are interchangeable so the scan flow can prefer the on-device model
/// when it's available (`FoundationModelsWorkoutScanParser`) and fall back to the
/// deterministic notation parser (`HeuristicWorkoutScanParser`) otherwise.
protocol WorkoutScanParsing: Sendable {
    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft
}

/// The always-available, deterministic parser. Pure synchronous logic lives in
/// `HandwrittenWorkoutParser`; this is the async protocol wrapper.
nonisolated struct HeuristicWorkoutScanParser: WorkoutScanParsing {
    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parse(ocrText, referenceDate: referenceDate)
    }
}

/// Deterministic parser for common handwritten gym notation. Pure and synchronous so
/// it is fully unit-testable without Vision or the on-device model.
///
/// Supported per-line patterns (the rules are intentionally explicit so behavior is
/// predictable and regression-tested):
///   • Date headers — `M/D`, `M/D/YY`, `M/D/YYYY`, `YYYY-MM-DD` set the session date.
///   • Word-only lines (no digits) become the workout title.
///   • `Name S x R`            → S sets of R reps           (e.g. "Squat 5x5")
///   • `Name S x R @ W[unit]`  → S sets of R reps at weight (e.g. "Bench 3x5 @ 135 lb")
///   • `Name S x R W`          → trailing bare number is the weight (e.g. "Squat 5x5 225")
///   • `Name S x R x W`        → embedded weight             (e.g. "Squat 5x5x225")
///   • `Name W x R` where W ≥ 25 → a single weight×reps work set (e.g. "Deadlift 315x5")
///   • `Name W1xR1 W2xR2 …`    → one weight×reps set per pair (e.g. "Bench 135x5 155x3 175x1")
///   • `Name S x Ns` / `S x M:SS` → S timed sets             (e.g. "Plank 3x30s")
///   • `Name <distance> <time>`  → one cardio set            (e.g. "Run 5k 25:00")
///   • `Name R`                → one set of R reps (bodyweight)
nonisolated enum HandwrittenWorkoutParser {

    /// A single `AxB` token is treated as weight×reps (one set) rather than sets×reps
    /// once `A` reaches this value — real set counts almost never do, real loads almost
    /// always do.
    private static let weightDisambiguationThreshold: Double = 25

    static func parse(_ text: String, referenceDate: Date) -> ParsedWorkoutDraft {
        var draft = ParsedWorkoutDraft()
        var titleAssigned = false

        for rawLine in text.split(whereSeparator: { $0.isNewline }).map(String.init) {
            var line = normalize(rawLine)
            guard !line.isEmpty else { continue }

            // Pull a date out of the line (first one wins for the session date) and strip
            // it so a "Tuesday 3/5" header isn't mistaken for an exercise.
            if let match = detectDate(in: line, referenceDate: referenceDate) {
                if draft.performedAt == nil { draft.performedAt = match.date }
                line = normalize(line.replacingCharacters(in: match.range, with: " "))
                guard !line.isEmpty else { continue }
            }

            // Word-only line → title.
            if isWordOnly(line) {
                if !titleAssigned, !isWeekday(line) {
                    draft.title = cleanTitle(line)
                    titleAssigned = true
                }
                continue
            }

            if let exercise = parseExerciseLine(line) {
                draft.exercises.append(exercise)
            }
        }

        return draft
    }

    // MARK: - Line classification

    private static func parseExerciseLine(_ line: String) -> ParsedExerciseDraft? {
        let tokens = line.split(separator: " ").map(String.init)
        guard let specStart = tokens.firstIndex(where: isSpecStart) else { return nil }
        let nameTokens = Array(tokens[..<specStart])
        let specTokens = Array(tokens[specStart...])
        guard !nameTokens.isEmpty else { return nil }

        let name = cleanName(nameTokens.joined(separator: " "))
        guard !name.isEmpty else { return nil }

        let sets = parseSpec(specTokens)
        guard !sets.isEmpty else { return nil }
        return ParsedExerciseDraft(name: name, sets: sets)
    }

    // MARK: - Spec parsing

    private enum BValue: Equatable {
        case reps(Int)
        case duration(Int)
    }

    private struct AxB {
        var a: Double
        var b: BValue
        var embeddedWeight: (Double, WeightUnit)?
    }

    private static func parseSpec(_ rawTokens: [String]) -> [ParsedSetDraft] {
        var axbs: [AxB] = []
        var weight: (value: Double, unit: WeightUnit)?
        var distance: (value: Double, unit: DistanceUnit)?
        var standaloneDuration: Int?
        var bareNumbers: [Double] = []
        var expectWeight = false

        for token in mergeSpecTokens(rawTokens) {
            let lower = token.lowercased()

            if lower == "@" { expectWeight = true; continue }

            if expectWeight {
                expectWeight = false
                // A number right after "@" is the load, with or without an explicit unit.
                if let w = parseWeight(lower) ?? Double(lower).map({ ($0, WeightUnit.lb) }) {
                    weight = weight ?? w
                    continue
                }
                // not a weight after all — fall through to normal classification
            }

            if lower.hasPrefix("@") {
                let rest = String(lower.dropFirst())
                if let w = parseWeight(rest) ?? Double(rest).map({ ($0, WeightUnit.lb) }) {
                    weight = weight ?? w
                    continue
                }
            }
            if let axb = parseAxB(lower) {
                axbs.append(axb)
                continue
            }
            if let dur = parseDuration(lower) {
                standaloneDuration = standaloneDuration ?? dur
                continue
            }
            if let dist = parseDistance(lower) {
                distance = distance ?? dist
                continue
            }
            if let w = parseWeight(lower) {
                weight = weight ?? w
                continue
            }
            if let n = Double(lower) {
                bareNumbers.append(n)
                continue
            }
        }

        return buildSets(
            axbs: axbs,
            weight: weight,
            distance: distance,
            standaloneDuration: standaloneDuration,
            bareNumbers: bareNumbers
        )
    }

    private static func buildSets(
        axbs: [AxB],
        weight: (value: Double, unit: WeightUnit)?,
        distance: (value: Double, unit: DistanceUnit)?,
        standaloneDuration: Int?,
        bareNumbers: [Double]
    ) -> [ParsedSetDraft] {
        if axbs.count == 1 {
            let axb = axbs[0]
            // "315x5" — A is the load, not a set count.
            if axb.a >= weightDisambiguationThreshold, case let .reps(reps) = axb.b, axb.embeddedWeight == nil {
                return [ParsedSetDraft(weight: axb.a, weightUnit: weight?.unit ?? .lb, reps: reps)]
            }

            // Sets × reps (or sets × per-set duration).
            let count = max(1, Int(axb.a))
            let resolvedWeight = axb.embeddedWeight ?? weight.map { ($0.value, $0.unit) }
                ?? trailingWeight(from: bareNumbers, hasDuration: { if case .duration = axb.b { return true } else { return false } }())
            let template: ParsedSetDraft
            switch axb.b {
            case .reps(let reps):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? .lb,
                    reps: reps
                )
            case .duration(let seconds):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? .lb,
                    durationSeconds: seconds
                )
            }
            return Array(repeating: template, count: count).map { var s = $0; s.id = UUID(); return s }
        }

        if axbs.count >= 2 {
            // Weight × reps pairs: "135x5 155x3 175x1".
            return axbs.compactMap { axb in
                guard case let .reps(reps) = axb.b else { return nil }
                return ParsedSetDraft(weight: axb.a, weightUnit: weight?.unit ?? .lb, reps: reps)
            }
        }

        // No `AxB` — cardio, timed, or a single bare value.
        if distance != nil || standaloneDuration != nil {
            return [ParsedSetDraft(
                weight: weight?.value,
                weightUnit: weight?.unit ?? .lb,
                distance: distance?.value,
                distanceUnit: distance?.unit ?? .meters,
                durationSeconds: standaloneDuration
            )]
        }
        if bareNumbers.count == 1, let reps = intIfWhole(bareNumbers[0]) {
            return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? .lb, reps: reps)]
        }
        if let weight {
            return [ParsedSetDraft(weight: weight.value, weightUnit: weight.unit)]
        }
        return []
    }

    /// A single trailing bare number after a sets×reps token is read as the load
    /// ("Squat 5x5 225"). Skipped when the set already carries a duration.
    private static func trailingWeight(from bareNumbers: [Double], hasDuration: Bool) -> (Double, WeightUnit)? {
        guard !hasDuration, bareNumbers.count == 1 else { return nil }
        return (bareNumbers[0], .lb)
    }

    // MARK: - Token parsers

    /// Glue split tokens back together so human spacing doesn't defeat the classifiers:
    /// `3 x 5` → `3x5`, `@ 135 lb` → `@135lb`, `100 kg` → `100kg`, `5 k` → `5k`.
    private static func mergeSpecTokens(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            var current = tokens[index]
            var next = index + 1
            while next < tokens.count, shouldMerge(current, tokens[next]) {
                current += tokens[next]
                next += 1
            }
            result.append(current)
            index = next
        }
        return result
    }

    private static func shouldMerge(_ current: String, _ next: String) -> Bool {
        let endsWithDigit = current.last?.isNumber ?? false
        let nextStartsWithDigit = next.first?.isNumber ?? false
        if endsWithDigit, isPureUnit(next) { return true }      // 135 + lb, 5 + k, 25 + min
        if endsWithDigit, next.lowercased() == "x" { return true } // 3 + x
        if current.lowercased().hasSuffix("x"), nextStartsWithDigit { return true } // 3x + 5
        if current == "@", nextStartsWithDigit { return true }     // @ + 135
        return false
    }

    private static let pureUnits: Set<String> = [
        "lb", "lbs", "kg", "kgs", "#",
        "km", "k", "mi", "mile", "miles", "m", "meter", "meters", "yd", "yard", "yards", "ft", "feet",
        "h", "hr", "hrs", "hour", "hours", "min", "mins", "minute", "minutes",
        "s", "sec", "secs", "second", "seconds"
    ]

    private static func isPureUnit(_ token: String) -> Bool {
        pureUnits.contains(token.lowercased())
    }

    private static func parseAxB(_ token: String) -> AxB? {
        guard token.contains("x") else { return nil }
        let parts = token.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let a = Double(parts[0]), a > 0 else { return nil }
        guard let b = parseBValue(parts[1]) else { return nil }
        var embedded: (Double, WeightUnit)?
        if parts.count == 3 {
            embedded = parseWeight(parts[2]) ?? Double(parts[2]).map { ($0, .lb) }
        }
        return AxB(a: a, b: b, embeddedWeight: embedded)
    }

    private static func parseBValue(_ s: String) -> BValue? {
        if let dur = parseDuration(s) { return .duration(dur) }
        if let reps = intIfWhole(Double(s)) { return .reps(reps) }
        return nil
    }

    private static func parseWeight(_ token: String) -> (Double, WeightUnit)? {
        if let unitRange = token.rangeOfUnitSuffix(["lbs", "lb", "kgs", "kg", "#"]) {
            let numberPart = String(token[..<unitRange.lowerBound])
            guard let value = Double(numberPart) else { return nil }
            let unit = token[unitRange].lowercased()
            return (value, (unit == "kg" || unit == "kgs") ? .kg : .lb)
        }
        return nil
    }

    private static func parseDistance(_ token: String) -> (Double, DistanceUnit)? {
        let units: [(String, DistanceUnit)] = [
            ("km", .kilometers), ("k", .kilometers),
            ("miles", .miles), ("mile", .miles), ("mi", .miles),
            ("meters", .meters), ("meter", .meters), ("m", .meters),
            ("yards", .yards), ("yard", .yards), ("yd", .yards),
            ("feet", .feet), ("ft", .feet)
        ]
        for (suffix, unit) in units {
            guard token.hasSuffix(suffix) else { continue }
            let numberPart = String(token.dropLast(suffix.count))
            guard let value = Double(numberPart), value > 0 else { continue }
            return (value, unit)
        }
        return nil
    }

    private static func parseDuration(_ token: String) -> Int? {
        if token.contains(":") {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let numbers = parts.compactMap { Int($0) }
            guard numbers.count == parts.count else { return nil }
            switch numbers.count {
            case 2: return numbers[0] * 60 + numbers[1]            // mm:ss
            case 3: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2] // h:mm:ss
            default: return nil
            }
        }
        let units: [(String, Int)] = [
            ("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600),
            ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60),
            ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1)
        ]
        for (suffix, multiplier) in units {
            guard token.hasSuffix(suffix) else { continue }
            let numberPart = String(token.dropLast(suffix.count))
            guard let value = Double(numberPart), value >= 0 else { continue }
            return Int((value * Double(multiplier)).rounded())
        }
        return nil
    }

    // MARK: - Dates

    private struct DateMatch { var date: Date; var range: Range<String.Index> }

    private static let slashDateRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#
    )
    private static let isoDateRegex = try? NSRegularExpression(
        pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#
    )

    private static func detectDate(in line: String, referenceDate: Date) -> DateMatch? {
        if let iso = isoDateRegex, let match = firstMatch(iso, in: line),
           let y = intGroup(match, 1, line), let mo = intGroup(match, 2, line), let d = intGroup(match, 3, line),
           let date = makeDate(year: y, month: mo, day: d),
           let range = Range(match.range, in: line) {
            return DateMatch(date: date, range: range)
        }
        if let slash = slashDateRegex, let match = firstMatch(slash, in: line),
           let mo = intGroup(match, 1, line), let d = intGroup(match, 2, line) {
            let referenceYear = calendar.component(.year, from: referenceDate)
            let year: Int
            if let raw = intGroup(match, 3, line) {
                year = raw < 100 ? 2000 + raw : raw
            } else {
                year = referenceYear
            }
            guard (1...12).contains(mo), (1...31).contains(d),
                  let date = makeDate(year: year, month: mo, day: d),
                  let range = Range(match.range, in: line) else { return nil }
            return DateMatch(date: date, range: range)
        }
        return nil
    }

    private static func firstMatch(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, _ line: String) -> Int? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: line) else { return nil }
        return Int(line[range])
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

    // MARK: - Helpers

    private static func normalize(_ line: String) -> String {
        var result = line
        for multiply in ["×", "✕", "✗", "*", "·"] {
            result = result.replacingOccurrences(of: multiply, with: "x")
        }
        result = result.replacingOccurrences(of: ",", with: " ")
        let collapsed = result.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSpecStart(_ token: String) -> Bool {
        if token == "@" || token.hasPrefix("@") { return true }
        return token.contains(where: \.isNumber)
    }

    private static func isWordOnly(_ line: String) -> Bool {
        guard line.contains(where: \.isLetter) else { return false }
        return !line.contains(where: \.isNumber) && !line.contains("@")
    }

    private static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—•*").union(.whitespaces))
    }

    private static func cleanTitle(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—•").union(.whitespaces))
        return trimmed.isEmpty ? "Scanned workout" : trimmed
    }

    private static let weekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun"
    ]

    private static func isWeekday(_ line: String) -> Bool {
        weekdays.contains(line.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private static func intIfWhole(_ value: Double?) -> Int? {
        guard let value, value >= 0, value == value.rounded() else { return nil }
        return Int(value)
    }
}

private extension String {
    /// Range of the longest matching unit suffix from `candidates` (checked in order),
    /// but only when at least one digit precedes it.
    nonisolated func rangeOfUnitSuffix(_ candidates: [String]) -> Range<String.Index>? {
        let lower = lowercased()
        for candidate in candidates where lower.hasSuffix(candidate) {
            let start = index(endIndex, offsetBy: -candidate.count)
            guard start > startIndex, self[..<start].contains(where: \.isNumber) else { continue }
            return start..<endIndex
        }
        return nil
    }
}
