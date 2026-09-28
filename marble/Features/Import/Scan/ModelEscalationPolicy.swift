import Foundation

/// Decides when a deterministic parse is good enough to skip the on-device model.
///
/// The notation parser never says "I'm unsure": it either drops a line (which the
/// callers already treat as "ask the model") or it claims the line — and some of
/// its claims are confidently wrong. "Bench 225x5x3" becomes 225 sets at 3 lb;
/// "bench 3x8 185, incline db 3x10 60s" becomes one exercise at 3 lb; "Ran a mile
/// in 8 minutes then 3 sets of 20 pushups" becomes an exercise named "Ran a mile
/// in". None of those drop a line, so a dropped-lines gate alone skips the model
/// exactly when it is needed.
///
/// This policy looks for the fingerprints of those misreads — impossible set
/// counts, loads that are really set counts, prose in exercise names, two
/// movements joined on one line, and a stray load the parser ignored — and
/// escalates only then. Clean notation (the eval corpus's notation tier) must
/// never trip it: the model pass costs seconds per segment, and the arbiter
/// would keep the deterministic parse anyway.
///
/// Pure and synchronous: source text in, verdict out.
nonisolated enum ModelEscalationPolicy {

    /// Why a deterministic draft looks implausible. Exposed for tests and
    /// diagnostics; callers only need the Bool.
    enum Reason: Equatable, Sendable {
        /// More sets than any real exercise has (outside EMOM work).
        case implausibleSetCount
        /// A load below any real bar or dumbbell weight while a load-sized
        /// number sits on the same line — a set count read as the weight.
        case loadLooksLikeSetCount
        /// The exercise name carries verbs, prepositions, or connectives.
        case proseInName
        /// One source line holds two movements ("…, incline db 3x10",
        /// "… then 3x10 pushups", or two sets×reps groups).
        case multipleMovementsOnLine
        /// A sets×reps exercise has no load, yet a load-sized number is on
        /// its line ("Curls 3x12 with 25s").
        case ignoredLoad
    }

    /// Sets beyond this are a misread ("225x5x3" → 225 sets), except EMOMs.
    static let maxPlausibleSetCount = 20

    /// The one-stop gate both import paths share: run the model when the
    /// deterministic parser dropped a meaningful line, produced nothing, or
    /// produced something implausible. Date headers that split sessions are
    /// consumed rather than dropped; they are filtered anyway so a leftover
    /// header never forces a model pass.
    static func shouldRunModel(
        for result: WorkoutParseResult,
        sourceText: String,
        referenceDate: Date
    ) -> Bool {
        let meaningfulDrops = result.droppedLines.filter { line in
            !HandwrittenWorkoutParser.isSessionSplitHeader(line, referenceDate: referenceDate)
        }
        guard meaningfulDrops.isEmpty, result.draft.hasContent else { return true }
        return deterministicDraftNeedsModel(result.draft, sourceText: sourceText)
    }

    /// True when a complete-looking deterministic draft is implausible enough
    /// that the model should get a look.
    static func deterministicDraftNeedsModel(_ draft: ParsedWorkoutDraft, sourceText: String) -> Bool {
        !reasons(for: draft, sourceText: sourceText).isEmpty
    }

    static func reasons(for draft: ParsedWorkoutDraft, sourceText: String) -> [Reason] {
        let lines = sourceText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var found: [Reason] = []
        func note(_ reason: Reason) {
            if !found.contains(reason) { found.append(reason) }
        }

        let mentionsEMOM = sourceText.lowercased().contains("emom")
            || sourceText.lowercased().contains("every minute")

        for exercise in draft.importableExercises {
            if exercise.sets.count > maxPlausibleSetCount, !mentionsEMOM {
                note(.implausibleSetCount)
            }
            if nameReadsAsProse(exercise.trimmedName) {
                note(.proseInName)
            }

            let sourceLines = Self.lines(lines, naming: exercise.trimmedName)
            let lineLoads = sourceLines.flatMap(loadSizedNumbers)
            let hasLoadSizedNumber = lineLoads.contains { $0 >= 45 }

            let lightLoad = exercise.sets.contains { set in
                guard let weight = set.weight else { return false }
                return weight < (set.weightUnit == .kg ? 10 : 25)
            }
            if lightLoad, hasLoadSizedNumber {
                note(.loadLooksLikeSetCount)
            }

            let setsByReps = exercise.sets.contains { $0.reps != nil }
                && exercise.sets.allSatisfy { $0.weight == nil && $0.distance == nil && $0.durationSeconds == nil }
            if setsByReps, sourceLines.flatMap(bareLoadCandidates).contains(where: { $0 >= 20 }) {
                note(.ignoredLoad)
            }
        }

        if lines.contains(where: joinsTwoMovements) {
            note(.multipleMovementsOnLine)
        }
        return found
    }

    // MARK: - Names

    /// Words that belong to a sentence, not a movement name. "and" is allowed
    /// only inside the Olympic compounds ("Clean and Jerk", "Clean and Press").
    private static let proseWords: Set<String> = [
        "ran", "did", "then", "with", "for", "in", "at", "and", "dropped",
        "drop", "backoff", "after", "of", "was", "went", "to"
    ]

    static func nameReadsAsProse(_ name: String) -> Bool {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        for (index, word) in words.enumerated() where proseWords.contains(word) {
            if word == "and", index > 0, words[index - 1] == "clean" { continue }
            if word == "to", words.contains("sit") { continue }
            return true
        }
        return false
    }

    /// Source lines that mention the exercise. The parser only trims and
    /// title-cleans names, so a case-insensitive containment check finds the
    /// line; a name on its own line (Strong/Hevy layout) finds a line with no
    /// numbers, which correctly checks nothing.
    private static func lines(_ lines: [String], naming name: String) -> [String] {
        let needle = name.lowercased()
        guard !needle.isEmpty else { return [] }
        return lines.filter { $0.lowercased().contains(needle) }
    }

    // MARK: - Numbers on a line

    /// Units and keywords that make an adjacent number something other than a load.
    private static let nonLoadSuffixes: Set<String> = [
        "s", "sec", "secs", "second", "seconds", "min", "mins", "minute", "minutes",
        "m", "meter", "meters", "km", "k", "mi", "mile", "miles", "yd", "yds", "yards",
        "ft", "feet", "reps", "rep", "sets", "set", "%", "rounds", "cal", "cals"
    ]

    /// Every number on the line that could be a load: the factors of NxM
    /// groups and standalone numbers, minus rest, tempo, durations, distances,
    /// percentages, and dates.
    static func loadSizedNumbers(in line: String) -> [Double] {
        let tokens = tokenize(line)
        var numbers: [Double] = []
        for (index, token) in tokens.enumerated() {
            if isContextExcluded(tokens, at: index) { continue }
            if let group = factors(of: token) {
                numbers.append(contentsOf: group)
            } else if let value = loadValue(token), !followedByNonLoadUnit(tokens, at: index) {
                numbers.append(value)
            }
        }
        return numbers
    }

    /// Standalone numbers only (not NxM factors) that read as a load — "185",
    /// "25s" (a pair of 25s), "60kg". Used to spot a load the parser ignored.
    static func bareLoadCandidates(in line: String) -> [Double] {
        let tokens = tokenize(line)
        var numbers: [Double] = []
        for (index, token) in tokens.enumerated() {
            if isContextExcluded(tokens, at: index) || factors(of: token) != nil { continue }
            if let value = loadValue(token, allowPluralS: true), !followedByNonLoadUnit(tokens, at: index) {
                numbers.append(value)
            }
        }
        return numbers
    }

    /// Lowercased tokens with "3 x 5" / "3 × 5" glued into "3x5" and commas
    /// that separate clauses (not digit grouping) split off.
    private static func tokenize(_ line: String) -> [String] {
        var text = line.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        text = text.replacingOccurrences(
            of: #"(\d)\s*[x*]\s*(\d)"#, with: "$1x$2", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression
        )
        text = text.replacingOccurrences(of: ",", with: " , ")
        text = text.replacingOccurrences(of: "(", with: " ( ")
        text = text.replacingOccurrences(of: ")", with: " ) ")
        // Trailing label punctuation ("min:", "squats:") is not part of the word.
        return text.split(whereSeparator: \.isWhitespace).map { token in
            var word = String(token)
            while word.count > 1, let last = word.last, ":;.".contains(last) { word.removeLast() }
            return word
        }
    }

    /// Rest ("rest 90"), tempo ("tempo 20x1", "(31x1)"), RPE, and dates never
    /// carry a load.
    private static func isContextExcluded(_ tokens: [String], at index: Int) -> Bool {
        let token = tokens[index]
        if token.contains("/") || token.contains(":") || token.hasSuffix("%") { return true }
        if index > 0 {
            let previous = tokens[index - 1]
            if ["rest", "tempo", "rpe", "@rpe", "(", "rested", "resting"].contains(previous) { return true }
        }
        if index + 1 < tokens.count, ["rest", "%"].contains(tokens[index + 1]) { return true }
        return false
    }

    private static func followedByNonLoadUnit(_ tokens: [String], at index: Int) -> Bool {
        guard index + 1 < tokens.count else { return false }
        return nonLoadSuffixes.contains(tokens[index + 1])
    }

    /// "3x5" → [3, 5]; "225x5x3" → [225, 5, 3]. Unit suffixes on the last
    /// factor ("3x30s", "4x20m") make it a duration/distance group, which
    /// keeps only the leading count.
    private static func factors(of token: String) -> [Double]? {
        let parts = token.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let first = Double(parts[0]) else { return nil }
        var values = [first]
        for part in parts.dropFirst() {
            if let value = Double(part) {
                values.append(value)
            } else if let leading = part.split(whereSeparator: { !$0.isNumber && $0 != "." }).first,
                      part.first?.isNumber == true, Double(leading) != nil {
                // "30s", "20m", "8-10": a timed/distance/range factor, not a load.
                continue
            } else if part.first?.isNumber == false {
                // "3xamrap", "2xfailure".
                continue
            } else {
                return nil
            }
        }
        return values
    }

    /// "185", "185lb", "60kg", "185#", and — when `allowPluralS` — "25s"
    /// (dumbbell shorthand).
    private static func loadValue(_ token: String, allowPluralS: Bool = false) -> Double? {
        var body = token
        if body.hasPrefix("@") { body.removeFirst() }
        for suffix in ["lbs", "lb", "kgs", "kg", "#"] where body.hasSuffix(suffix) {
            body.removeLast(suffix.count)
            break
        }
        if allowPluralS, body.hasSuffix("s") { body.removeLast() }
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(body)
    }

    // MARK: - Two movements on one line

    /// Words that can follow a number without naming a movement.
    private static let clauseNoise: Set<String> = [
        "rest", "rested", "resting", "lb", "lbs", "kg", "kgs", "pounds", "pound",
        "kilos", "kg.", "s", "sec", "secs", "seconds", "min", "mins", "minutes",
        "reps", "rep", "sets", "set", "x", "at", "@", "rpe", "tempo", "each",
        "side", "leg", "arm", "per", "between", "for", "a", "the", "with", "of",
        "and", "then", "to", "on", "in", "about", "around", "approx", "bw",
        "bodyweight", "amrap", "failure", "round", "rounds", "total", "sec.",
        "min.", "m", "km", "mi", "miles", "mile", "meters", "meter", "yd", "yards"
    ]

    static func joinsTwoMovements(_ line: String) -> Bool {
        let tokens = tokenize(line)
        if tokens.contains("then"), tokens.contains(where: { $0.contains(where: \.isNumber) }) {
            return true
        }

        // Two sets×reps groups with set-count-sized leading factors
        // ("3x5 … 2x8"). Weight×reps ladders ("135x5 155x3") lead with loads
        // and stay one movement.
        var setGroups = 0
        for (index, token) in tokens.enumerated() where !isContextExcluded(tokens, at: index) {
            if let group = factors(of: token), let lead = group.first,
               lead < 25, lead >= 1, group.count >= 2 {
                setGroups += 1
            }
        }
        if setGroups >= 2 { return true }

        // Comma clauses that each name something and carry a number.
        let clauses = line.lowercased()
            .replacingOccurrences(of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
            .split(separator: ",")
            .map(String.init)
        let movementClauses = clauses.filter(clauseNamesMovementWithNumbers)
        return movementClauses.count >= 2
    }

    private static func clauseNamesMovementWithNumbers(_ clause: String) -> Bool {
        let tokens = tokenize(clause)
        guard tokens.contains(where: { $0.contains(where: \.isNumber) }) else { return false }
        return tokens.contains { token in
            token.count >= 2
                && token.allSatisfy(\.isLetter)
                && !clauseNoise.contains(token)
        }
    }
}
