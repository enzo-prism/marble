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
///   • `Name R`                → one set of R reps (bodyweight); a lone number ≥ 25
///     is a load instead ("Bench 225" → weight, "Pushups 20" → reps)
///   • `Name S by R`           → "by" between numbers reads as "x" (e.g. "press 5 by 5")
///   • `Name W for a single/double/triple` → one set of 1/2/3 reps at W
///   • `Name S x R1-R2`        → rep range; the lower bound wins (e.g. "Calf raises 4x8-10")
///   • `Name S x D<unit>`      → S distance sets (e.g. "Sprints 4x20m", "4 × 20-meter")
///   • `SxB Name …`            → spec-first lines fall back to the run of word tokens
///     for the name (e.g. "4x20m accelerations at 85-90%" → "accelerations")
///   • Intensity percentages ("85%", "85-90%") are noise — never a load or rep count.
///   • En/em dashes normalize to "-"; a hyphen gluing a number to a unit word is
///     dropped ("20-meter" → "20meter") while digit-digit hyphens ("8-10") survive.
///   • `… rest 90s` / `… 90s rest` → rest between sets, applied to every set on
///     the line. A bare number after "rest" is seconds when ≥ 15, minutes below
///     ("rest 90" → 90 s, "rest 2" → 2 min). A line that is *only* rest notation
///     ("rest 2 min between sets") applies to the previous exercise's sets.
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

            // A line that is only rest notation belongs to the previous
            // exercise; without this, "Rest 90s" would become an exercise.
            if let rest = restOnlyLineSeconds(line) {
                if let lastIndex = draft.exercises.indices.last {
                    for setIndex in draft.exercises[lastIndex].sets.indices {
                        let existing = draft.exercises[lastIndex].sets[setIndex].restSeconds
                        draft.exercises[lastIndex].sets[setIndex].restSeconds = existing ?? rest
                    }
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
        var nameTokens = Array(tokens[..<specStart])
        let specTokens = Array(tokens[specStart...])
        // Leading narration verbs/particles ("worked up to 225 on bench", "did pull
        // ups 4x10") are not exercise names. Only the prefix is stripped, so names
        // like "Warm up" or "Step to box" keep their inner words.
        while let first = nameTokens.first, nameFillerPrefixes.contains(first.lowercased()) {
            nameTokens.removeFirst()
        }
        guard !nameTokens.isEmpty else { return parseLeadingSpecLine(tokens) }

        let name = cleanName(nameTokens.joined(separator: " "))
        guard !name.isEmpty else { return nil }

        let sets = parseSpec(specTokens)
        guard !sets.isEmpty else { return nil }
        return ParsedExerciseDraft(name: name, sets: sets)
    }

    /// Narration words that may prefix a name but are never part of it
    /// ("worked up to …", "did pull ups …", "I …", "then some curls …").
    private static let nameFillerPrefixes: Set<String> = [
        "worked", "up", "to", "did", "i", "then", "some"
    ]

    /// Words that connect a spec to its exercise name without being part of it
    /// ("4x20m accelerations at 85-90%", "3x10 goblet squats with a 50 pound dumbbell").
    private static let specFillerWords: Set<String> = [
        "at", "with", "a", "an", "the", "of", "for", "per", "each", "using",
        "on", "side", "leg", "legs", "arm", "arms",
        "worked", "up", "to", "did", "i", "then", "some"
    ]

    /// Fallback for lines that lead with the numbers instead of the name
    /// ("4x20meter accelerations at 85-90%", "worked up to 225 on bench for a
    /// double"). The name is the first contiguous run of word-only tokens that
    /// yields anything once fillers are excluded; the spec is every token carrying
    /// a digit (plus rep words like "double"), in original order. An empty
    /// fallback name drops the line as before.
    private static func parseLeadingSpecLine(_ tokens: [String]) -> ParsedExerciseDraft? {
        let merged = mergeSpecTokens(tokens)
        var nameTokens: [String] = []
        var specTokens: [String] = []
        var nameRunEnded = false
        for token in merged {
            let lower = token.lowercased()
            if token.contains(where: \.isNumber) || repWordValues[lower] != nil {
                specTokens.append(token)
                // A spec token only closes the name once a name actually started,
                // so "worked up to 225 on bench …" still reaches "bench".
                if !nameTokens.isEmpty { nameRunEnded = true }
                continue
            }
            guard token.contains(where: \.isLetter), !nameRunEnded else { continue }
            if !specFillerWords.contains(lower) {
                nameTokens.append(token)
            }
        }

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
        case distance(Double, DistanceUnit)
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
        var repRange: Int?
        var wordReps: Int?
        var bareNumbers: [Double] = []
        var expectWeight = false

        // Pull rest notation out first so "90s rest" isn't read as a timed set.
        let (tokens, restSeconds) = extractRest(mergeSpecTokens(rawTokens))

        for token in tokens {
            let lower = token.lowercased()

            // Intensity percentages ("85%", "85-90%") are noise — never a load,
            // rep count, or bare number.
            if lower.hasSuffix("%") { continue }

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
            if let range = parseRepRange(lower) {
                // "8-10" as its own token is a rep range, never a load.
                repRange = repRange ?? range
                continue
            }
            if let reps = repWordValues[lower] {
                // "for a single/double/triple" — a spelled-out rep count.
                wordReps = wordReps ?? reps
                continue
            }
            if let n = Double(lower) {
                bareNumbers.append(n)
                continue
            }
        }

        let sets = buildSets(
            axbs: axbs,
            weight: weight,
            distance: distance,
            standaloneDuration: standaloneDuration,
            repRange: repRange,
            wordReps: wordReps,
            bareNumbers: bareNumbers
        )
        guard let restSeconds else { return sets }
        return sets.map { set in
            var updated = set
            updated.restSeconds = restSeconds
            return updated
        }
    }

    // MARK: - Rest notation

    private static let restMarkers: Set<String> = ["rest", "rests", "resting"]

    /// Removes rest notation from the merged spec tokens and returns the rest
    /// duration it described, if any. Handles "rest 90s", "rest 90", "rest 2min",
    /// and "90s rest".
    private static func extractRest(_ tokens: [String]) -> (tokens: [String], restSeconds: Int?) {
        var remaining = tokens
        guard let markerIndex = remaining.firstIndex(where: { restMarkers.contains($0.lowercased()) }) else {
            return (remaining, nil)
        }

        // "rest 90s" / "rest 90" — the value follows the marker.
        if markerIndex + 1 < remaining.count {
            let next = remaining[markerIndex + 1].lowercased()
            if let duration = parseDuration(next) {
                remaining.removeSubrange(markerIndex...(markerIndex + 1))
                return (remaining, duration)
            }
            if let value = Double(next), value > 0 {
                remaining.removeSubrange(markerIndex...(markerIndex + 1))
                // Bare numbers are seconds when ≥ 15 ("rest 90"), minutes below
                // ("rest 2") — nobody rests 2 seconds or 90 minutes between sets.
                return (remaining, value >= 15 ? Int(value) : Int(value * 60))
            }
        }

        // "90s rest" — the value precedes the marker.
        if markerIndex > 0, let duration = parseDuration(remaining[markerIndex - 1].lowercased()) {
            remaining.removeSubrange((markerIndex - 1)...markerIndex)
            return (remaining, duration)
        }

        remaining.remove(at: markerIndex)
        return (remaining, nil)
    }

    /// When a whole line is nothing but rest notation ("rest 2 min between sets"),
    /// returns its duration; the caller applies it to the previous exercise.
    private static func restOnlyLineSeconds(_ line: String) -> Int? {
        let tokens = mergeSpecTokens(line.split(separator: " ").map(String.init))
        guard tokens.contains(where: { restMarkers.contains($0.lowercased()) }) else { return nil }
        let (remaining, restSeconds) = extractRest(tokens)
        guard let restSeconds else { return nil }
        // Anything left with a digit means the line carried real work too.
        guard !remaining.contains(where: { $0.contains(where: \.isNumber) }) else { return nil }
        return restSeconds
    }

    private static func buildSets(
        axbs: [AxB],
        weight: (value: Double, unit: WeightUnit)?,
        distance: (value: Double, unit: DistanceUnit)?,
        standaloneDuration: Int?,
        repRange: Int?,
        wordReps: Int?,
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
            case .distance(let value, let unit):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? .lb,
                    distance: value,
                    distanceUnit: unit
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
        if bareNumbers.count == 1 {
            let bare = bareNumbers[0]
            // "225 … for a double" — the bare number is the load, the word the reps.
            if let wordReps {
                return [ParsedSetDraft(weight: bare, weightUnit: weight?.unit ?? .lb, reps: wordReps)]
            }
            // A lone big number is a load ("Bench 225"), a small one a rep
            // count ("Pushups 20") — same threshold as the AxB disambiguation.
            if weight == nil, bare >= weightDisambiguationThreshold {
                return [ParsedSetDraft(weight: bare, weightUnit: .lb)]
            }
            if let reps = intIfWhole(bare) {
                return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? .lb, reps: reps)]
            }
        }
        // A lone rep range ("Curls 8-10") — the lower bound is the target.
        if let repRange {
            return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? .lb, reps: repRange)]
        }
        // A rep word with an explicit load ("Bench 225lb for a double") or alone.
        if let wordReps {
            return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? .lb, reps: wordReps)]
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
        var tokens = tokens
        // "5 by 5" reads as "5 x 5" — but only between numbers, so a "by" inside an
        // exercise name ("pull by cable") stays put.
        for index in tokens.indices where tokens[index].lowercased() == "by" {
            guard index > 0, index + 1 < tokens.count,
                  tokens[index - 1].last?.isNumber == true,
                  tokens[index + 1].first?.isNumber == true else { continue }
            tokens[index] = "x"
        }
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
        "pound", "pounds", "kilogram", "kilograms", "kilo", "kilos",
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
        if let lower = parseRepRange(s) { return .reps(lower) }
        if let dist = parseDistance(s) { return .distance(dist.0, dist.1) }
        return nil
    }

    /// Spelled-out rep counts used with a max-effort load ("for a double").
    private static let repWordValues: [String: Int] = [
        "single": 1, "double": 2, "triple": 3
    ]

    /// "8-10" — a rep range; the lower bound is the concrete target.
    private static func parseRepRange(_ token: String) -> Int? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              let low = intIfWhole(Double(parts[0])),
              let high = intIfWhole(Double(parts[1])),
              low > 0, high >= low else { return nil }
        return low
    }

    /// Longest-first so "pounds" is claimed before "pound" could shadow it.
    private static let weightUnitSuffixes: [String] = [
        "kilograms", "kilogram", "pounds", "pound", "kilos", "kilo",
        "lbs", "kgs", "lb", "kg", "#"
    ]

    private static func parseWeight(_ token: String) -> (Double, WeightUnit)? {
        if let unitRange = token.rangeOfUnitSuffix(weightUnitSuffixes) {
            let numberPart = String(token[..<unitRange.lowerBound])
            guard let value = Double(numberPart) else { return nil }
            let unit = token[unitRange].lowercased()
            // kg, kgs, kilo(s), kilogram(s) all lead with "k"; everything else is pounds.
            return (value, unit.hasPrefix("k") ? .kg : .lb)
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

    /// First explicit date found anywhere in `text` (`M/D`, `M/D/YY`, `YYYY-MM-DD`).
    /// Exposed so the model-backed parser can resolve the date it extracted with the
    /// same deterministic rules instead of asking the model to do calendar math.
    static func explicitDate(in text: String, referenceDate: Date) -> Date? {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            if let match = detectDate(in: String(line), referenceDate: referenceDate) {
                return match.date
            }
        }
        return nil
    }

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
        for dash in ["–", "—"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        result = attachHyphenatedUnits(result)
        result = result.replacingOccurrences(of: ",", with: " ")
        let collapsed = result.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops a hyphen that glues a number to a unit word so the token reads as one
    /// unit ("20-meter" → "20meter", "20-pound" → "20pound"). Digit-digit hyphens
    /// ("8-10", ISO dates) and word-word hyphens ("Rear-delt") are untouched.
    private static func attachHyphenatedUnits(_ line: String) -> String {
        let characters = Array(line)
        var result = ""
        result.reserveCapacity(characters.count)
        for (index, character) in characters.enumerated() {
            if character == "-", index > 0, index + 1 < characters.count,
               characters[index - 1].isNumber, characters[index + 1].isLetter {
                continue
            }
            result.append(character)
        }
        return result
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
