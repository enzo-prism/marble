import Foundation

/// Turns OCR / model text into structured workout data for review.
///
/// Conformers are interchangeable so the scan flow can prefer the on-device model
/// when it's available (`FoundationModelsWorkoutScanParser`) and fall back to the
/// deterministic notation parser (`HeuristicWorkoutScanParser`) otherwise.
/// Coarse stages of a text parse, surfaced as honest status text in the
/// processing UI. The deterministic pass is instant and the post-parse work
/// (library matching) is near-instant; the on-device model passes are where
/// the seconds go, so they are reported individually.
enum WorkoutParseStage: Sendable, Equatable {
    /// The deterministic notation pass (always runs, sub-millisecond).
    case readingNotation
    /// An on-device model reading: pass 1 is the notation rewrite, pass 2 the
    /// direct structured extraction. Only emitted when Apple Intelligence runs.
    case interpreting(pass: Int, of: Int)
    /// Reconciling candidates, then matching exercises against the library.
    case finalizing
}

protocol WorkoutScanParsing: Sendable {
    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft
}

extension WorkoutScanParsing {
    /// Staged variant for progress UI. The default forwards to the plain parse:
    /// conformers with a single fast pass (the deterministic parser) have no
    /// intermediate stages worth reporting.
    func parse(
        ocrText: String,
        referenceDate: Date,
        onStage: @Sendable (WorkoutParseStage) async -> Void
    ) async -> ParsedWorkoutDraft {
        await parse(ocrText: ocrText, referenceDate: referenceDate)
    }
}

/// The always-available, deterministic parser. Pure synchronous logic lives in
/// `HandwrittenWorkoutParser`; this is the async protocol wrapper.
nonisolated struct HeuristicWorkoutScanParser: WorkoutScanParsing {
    /// Unit assumed for weights written without one ("Bench 3x8 @ 100"). The
    /// caller passes the user's preference; `.lb` preserves the historic default.
    var defaultWeightUnit: WeightUnit = .lb

    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
        HandwrittenWorkoutParser.parseDetailed(
            ocrText,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit
        ).draft
    }
}

/// The draft plus the source lines nothing claimed. `droppedLines` powers the
/// review screen's "couldn't read these lines" section so a paste never loses
/// work silently.
nonisolated struct WorkoutParseResult: Equatable, Sendable {
    var draft: ParsedWorkoutDraft
    /// Non-empty lines that produced no exercise, title, date, or rest note.
    /// Raw (pre-normalization) text, trimmed, in source order.
    var droppedLines: [String]
}

/// Deterministic parser for common handwritten gym notation. Pure and synchronous so
/// it is fully unit-testable without Vision or the on-device model.
///
/// Supported per-line patterns (the rules are intentionally explicit so behavior is
/// predictable and regression-tested):
///   • Date headers — `M/D`, `M/D/YY`, `M/D/YYYY`, `YYYY-MM-DD` set the session date,
///     as do the relative words "yesterday"/"today"/"tonight"/"last night".
///   • Word-only lines (no digits) become the workout title — unless set rows or
///     bare set lines follow, in which case the line is the exercise name (the
///     Strong/Hevy/Notes layout: a name line, then its sets).
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
///   • Rep ladders / pyramids — one set per rung: `Name W x R1/R2/…` carries
///     the weight in the token (e.g. "Bench 225x5/3/1"), while a bare
///     "R1/R2/R3" or "S x R1-R2-R3" ladder takes its weight from "@ W". The
///     rungs are the ground truth: a leading count that disagrees with the
///     rung count loses ("Deadlift 1x5/3/1 @ 405" → 3 sets). Slash ladders
///     need 3+ rungs so "8/12" stays a date; dash ladders need 3+ so "8-10"
///     stays a rep range.
///   • `Name S x D<unit>`      → S distance sets (e.g. "Sprints 4x20m", "4 × 20-meter")
///   • `Name S x AMRAP` / `S x failure` → S sets with no rep target ("Pushups 3xAMRAP")
///   • `Set N: W x R`          → one set row (app export style), attached to the
///     current exercise (e.g. "Set 1: 60 kg x 10"); "Set N: R" is bodyweight reps
///   • `EMOM N min: R name`    → N sets of R reps of the named movement
///   • Bare spec lines (`185 x 8`) continue the previous exercise's sets.
///   • `SxB Name …`            → spec-first lines fall back to the run of word tokens
///     for the name (e.g. "4x20m accelerations at 85-90%" → "accelerations")
///   • Intensity percentages ("85%", "85-90%") are noise — never a load or rep count.
///   • Tempo notation is noise like percentages: "tempo 31x1", "tempo 3-0-1",
///     or a parenthesized "(31x1)" never becomes a second weight×reps pair.
///     Stripping is conservative — a bare "135x5" without the "tempo" keyword
///     or parentheses is still a real pair.
///   • Circuit/round header lines ("3 rounds:", "3 rounds of", "Circuit 1",
///     "three rounds:") are section markers, not exercises or titles. A
///     counted header multiplies the set count of the exercises that follow
///     until the next header; a bare label resets the count to one.
///   • Numbered session labels (`Day 1`, `Session 2: Legs`) are consumed as
///     titles, not as bodyweight exercises named "Day" / "Session".
///   • Spelled-out set phrases ("three sets of eight") mark the line as prose: the
///     line is left for the on-device model / unparsed-lines review rather than
///     being mangled into a plausible-looking wrong exercise.
///   • En/em dashes normalize to "-"; a hyphen gluing a number to a unit word is
///     dropped ("20-meter" → "20meter") while digit-digit hyphens ("8-10") survive.
///   • Digit-grouping commas are thousands separators, not token breaks
///     ("1,025 lb" → 1025, never 1).
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
        parseDetailed(text, referenceDate: referenceDate).draft
    }

    static func parseDetailed(
        _ text: String,
        referenceDate: Date,
        defaultWeightUnit: WeightUnit = .lb
    ) -> WorkoutParseResult {
        var draft = ParsedWorkoutDraft()
        var dropped: [String] = []
        var titleAssigned = false
        /// Set-count multiplier from a counted round header ("3 rounds:"):
        /// every movement in the round gets its parsed sets repeated once per
        /// round until the next header resets it.
        var roundMultiplier = 1
        /// A word-only line whose role is not yet known: the first one usually
        /// becomes the title, but a name line followed by set rows ("Squat" then
        /// "Set 1: 225 lb x 5") is an exercise name instead. Resolved when the
        /// next content line says which.
        var pendingWordLine: String? = nil

        /// Gives a pending word-only line its title role: the first one wins
        /// (existing behavior), later ones are noise unless a set row promotes
        /// them to an exercise name.
        func resolvePendingAsTitle() {
            guard let pending = pendingWordLine else { return }
            pendingWordLine = nil
            if !titleAssigned, !isWeekday(pending) {
                draft.title = cleanTitle(pending)
                titleAssigned = true
            }
        }

        /// Turns a pending word-only line into an exercise so following set rows
        /// / bare set lines attach to it. A promoted first line means there is no
        /// title, so the default stands.
        func promotePendingToExercise() {
            guard let pending = pendingWordLine, !isWeekday(pending) else { return }
            pendingWordLine = nil
            let name = promotedExerciseName(pending)
            guard !name.isEmpty else { return }
            draft.exercises.append(ParsedExerciseDraft(name: name, sets: []))
            if !titleAssigned { titleAssigned = true }
        }

        func recordDrop(_ rawLine: String) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { dropped.append(trimmed) }
        }

        for rawLine in text.split(whereSeparator: { $0.isNewline }).map(String.init) {
            var line = normalize(rawLine)
            guard !line.isEmpty else { continue }

            // Relative date words ("yesterday", "today") act like explicit date
            // headers: set the session date and leave the line.
            if let relative = detectRelativeDate(in: line, referenceDate: referenceDate) {
                if draft.performedAt == nil { draft.performedAt = relative.date }
                line = normalize(line.replacingCharacters(in: relative.range, with: " "))
                guard !line.isEmpty else { continue }
            }

            // Pull a date out of the line (first one wins for the session date) and strip
            // it so a "Tuesday 3/5" header isn't mistaken for an exercise.
            if let match = detectDate(in: line, referenceDate: referenceDate) {
                if draft.performedAt == nil { draft.performedAt = match.date }
                line = normalize(line.replacingCharacters(in: match.range, with: " "))
                guard !line.isEmpty else { continue }
            }

            // Numbered session labels (`Day 1`, `Session 2: Legs`) split a
            // paste, then stay in each segment. Consume them here so they
            // cannot parse as a bodyweight set named "Day" / "Session".
            if let remainder = numberedSessionHeaderRemainder(line) {
                resolvePendingAsTitle()
                if !titleAssigned {
                    let titleSource = remainder.isEmpty ? line : remainder
                    draft.title = cleanTitle(titleSource)
                    titleAssigned = true
                }
                continue
            }

            // Circuit/round header lines ("3 rounds:", "Circuit 1", "three
            // rounds:") are section markers, not exercises, titles, or drops.
            // Checked before the word-only branch because "three rounds:" has
            // no digits and would otherwise park as a pending title.
            if let header = parseRoundHeader(line) {
                resolvePendingAsTitle()
                switch header {
                case .counted(let count): roundMultiplier = max(1, count)
                case .labeled: roundMultiplier = 1
                }
                continue
            }

            // Word-only line → pending: title once resolved, or an exercise name
            // when set rows follow.
            if isWordOnly(line) {
                resolvePendingAsTitle()
                pendingWordLine = line
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

            // App-export set rows ("Set 1: 60 kg x 10") attach to the current
            // exercise, promoting a pending name line if one is waiting.
            if let set = parseSetRow(line, defaultWeightUnit: defaultWeightUnit) {
                promotePendingToExercise()
                if let lastIndex = draft.exercises.indices.last {
                    draft.exercises[lastIndex].sets.append(set)
                } else {
                    recordDrop(rawLine)
                }
                continue
            }

            // EMOM lines ("EMOM 10 min: 5 burpees") are a full exercise.
            if let emom = parseEmomLine(line) {
                resolvePendingAsTitle()
                draft.exercises.append(emom)
                continue
            }

            if var exercise = parseExerciseLine(line, defaultWeightUnit: defaultWeightUnit) {
                resolvePendingAsTitle()
                if roundMultiplier > 1 {
                    // "3 rounds: … pushups 10" — every movement in the round is
                    // performed once per round, so its sets repeat that many times.
                    exercise.sets = (0..<roundMultiplier).flatMap { _ in
                        exercise.sets.map { var copy = $0; copy.id = UUID(); return copy }
                    }
                }
                draft.exercises.append(exercise)
                continue
            }

            // Bare spec lines ("185 x 8") continue the previous exercise — the
            // natural one-exercise-per-block notes layout.
            if let sets = parseNamelessSpec(line, defaultWeightUnit: defaultWeightUnit) {
                promotePendingToExercise()
                if let lastIndex = draft.exercises.indices.last {
                    draft.exercises[lastIndex].sets.append(contentsOf: sets)
                } else {
                    recordDrop(rawLine)
                }
                continue
            }

            recordDrop(rawLine)
        }

        resolvePendingAsTitle()
        return WorkoutParseResult(draft: draft, droppedLines: dropped)
    }

    // MARK: - Line classification

    private static func parseExerciseLine(
        _ line: String,
        defaultWeightUnit: WeightUnit
    ) -> ParsedExerciseDraft? {
        // Spelled-out set phrases ("three sets of eight") are prose; mangling them
        // into a plausible-looking exercise is worse than listing the line as
        // unparsed, where the review screen (or the on-device model) can read it.
        guard !containsSpelledOutSets(line) else { return nil }

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
        guard !nameTokens.isEmpty else {
            return parseLeadingSpecLine(tokens, defaultWeightUnit: defaultWeightUnit)
        }

        let name = cleanName(nameTokens.joined(separator: " "))
        guard !name.isEmpty else { return nil }

        let sets = parseSpec(specTokens, defaultWeightUnit: defaultWeightUnit)
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
    /// double"). The name is the first contiguous run of word tokens that
    /// yields anything once fillers are excluded; the spec is every token carrying
    /// a digit (plus rep words like "double"), in original order. An empty
    /// fallback name drops the line as before.
    private static func parseLeadingSpecLine(
        _ tokens: [String],
        defaultWeightUnit: WeightUnit
    ) -> ParsedExerciseDraft? {
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

        let sets = parseSpec(specTokens, defaultWeightUnit: defaultWeightUnit)
        guard !sets.isEmpty else { return nil }
        return ParsedExerciseDraft(name: name, sets: sets)
    }

    /// A line of nothing but set notation ("185 x 8", "185x8 @ 90s rest"): every
    /// token is spec-ish and the spec yields at least one set. The caller attaches
    /// the sets to the previous exercise.
    private static func parseNamelessSpec(
        _ line: String,
        defaultWeightUnit: WeightUnit
    ) -> [ParsedSetDraft]? {
        let tokens = line.split(separator: " ").map(String.init)
        let merged = mergeSpecTokens(tokens)
        guard merged.allSatisfy(isSpecishToken) else { return nil }
        let sets = parseSpec(merged, defaultWeightUnit: defaultWeightUnit)
        return sets.isEmpty ? nil : sets
    }

    /// Tokens that can make up a nameless spec line: anything carrying a digit,
    /// "@", unit words, rest markers, and intensity percentages.
    private static func isSpecishToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        if token.contains(where: \.isNumber) { return true }
        if lower == "@" || lower.hasPrefix("@") { return true }
        if lower == "x" { return true }
        if isPureUnit(lower) { return true }
        if restMarkers.contains(lower) { return true }
        if lower.hasSuffix("%") { return true }
        return false
    }

    // MARK: - App-export set rows

    private static let setRowRegex = try? NSRegularExpression(
        pattern: #"(?i)^set\s*\d*\s*[:.)\-]?\s+(.+)$"#
    )
    /// "60 kg x 10", "225 lb x 5", "10 reps", "10". The weight group is optional
    /// so bodyweight rows parse too.
    private static let setRowSpecRegex = try? NSRegularExpression(
        pattern: #"(?i)^(?:(\d+(?:\.\d+)?)\s*(lb|lbs|kg|kgs|pound|pounds|kilo|kilos|kilogram|kilograms|#)?\s*[x×]\s*)?(\d+)\s*(?:reps?)?$"#
    )

    /// Hevy/Strong-style rows: "Set 1: 60 kg x 10". One row is one set; the
    /// exercise name comes from the surrounding block, not the row.
    private static func parseSetRow(
        _ line: String,
        defaultWeightUnit: WeightUnit
    ) -> ParsedSetDraft? {
        guard let regex = setRowRegex,
              let match = firstMatch(regex, in: line),
              let specRange = Range(match.range(at: 1), in: line) else { return nil }
        let spec = String(line[specRange])

        // Rest and RPE ride along when written on the row
        // ("Set 1: 225 x 5, rest 90s, RPE 8" — the comma is already a space).
        let (restStripped, restSeconds) = extractRest(
            mergeSpecTokens(spec.split(separator: " ").map(String.init))
        )
        let (tokens, difficulty) = extractRPE(restStripped)
        let body = tokens.joined(separator: " ")
        guard let specRegex = setRowSpecRegex,
              let specMatch = firstMatch(specRegex, in: body),
              let repsRange = Range(specMatch.range(at: 3), in: body),
              let reps = Int(body[repsRange]) else { return nil }

        var weight: Double?
        var unit = defaultWeightUnit
        if let weightRange = Range(specMatch.range(at: 1), in: body),
           let value = Double(body[weightRange]) {
            weight = value
            if let unitRange = Range(specMatch.range(at: 2), in: body) {
                unit = body[unitRange].lowercased().hasPrefix("k") ? .kg : .lb
            }
        }
        return ParsedSetDraft(
            weight: weight,
            weightUnit: unit,
            reps: reps,
            restSeconds: restSeconds,
            difficulty: difficulty
        )
    }

    // MARK: - EMOM

    private static let emomRegex = try? NSRegularExpression(
        pattern: #"(?i)^emom\s+(\d+)\s*(?:min|mins|minutes?)?\s*[:.\-–—]?\s*(\d+)\s+(.+)$"#
    )

    /// "EMOM 10 min: 5 burpees" → 10 sets of 5 burpees (one set per minute).
    private static func parseEmomLine(_ line: String) -> ParsedExerciseDraft? {
        guard let regex = emomRegex,
              let match = firstMatch(regex, in: line),
              let minutesRange = Range(match.range(at: 1), in: line),
              let minutes = Int(line[minutesRange]), minutes > 0,
              let repsRange = Range(match.range(at: 2), in: line),
              let reps = Int(line[repsRange]), reps > 0,
              let nameRange = Range(match.range(at: 3), in: line) else { return nil }
        let name = cleanName(String(line[nameRange]))
        guard !name.isEmpty else { return nil }
        let sets = (0..<minutes).map { _ in ParsedSetDraft(reps: reps) }
        return ParsedExerciseDraft(name: name, sets: sets)
    }

    // MARK: - Spelled-out set phrases

    /// Lines like "three sets of eight" or "five sets" are prose, not notation —
    /// flag them so the caller can route them to the model / unparsed review
    /// instead of building a plausible-looking wrong exercise.
    private static func containsSpelledOutSets(_ line: String) -> Bool {
        guard let regex = spelledSetsRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static let spelledSetsRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\s+(sets?|reps?|rounds?)\b|\bsets?\s+of\s+(?=[a-z])"#
    )

    // MARK: - Circuit / round headers

    /// A circuit/round header line: `.counted` carries the round count ("3
    /// rounds:"), `.labeled` is a bare section label ("Circuit 1").
    private enum RoundHeader {
        case counted(Int)
        case labeled
    }

    private static let countedRoundHeaderRegex = try? NSRegularExpression(
        pattern: #"(?i)^(\d+)\s+(?:rounds?|circuits?)(?:\s+of)?\s*:?$"#
    )
    private static let spelledRoundHeaderRegex = try? NSRegularExpression(
        pattern: #"(?i)^(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(?:rounds?|circuits?)(?:\s+of)?\s*:?$"#
    )
    private static let labeledRoundHeaderRegex = try? NSRegularExpression(
        pattern: #"(?i)^(?:circuit|round)\s*\d*\s*:?$"#
    )
    private static let spelledRoundCounts: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    /// Matches a line that is ONLY a circuit/round header — trailing content
    /// ("three rounds of 10 pushups, …", "round 2 of 3 felt easy") keeps its
    /// existing prose/dropped handling instead of being eaten here.
    private static func parseRoundHeader(_ line: String) -> RoundHeader? {
        if let regex = countedRoundHeaderRegex,
           let match = firstMatch(regex, in: line),
           let range = Range(match.range(at: 1), in: line),
           let count = Int(line[range]) {
            return .counted(count)
        }
        if let regex = spelledRoundHeaderRegex,
           let match = firstMatch(regex, in: line),
           let range = Range(match.range(at: 1), in: line),
           let count = spelledRoundCounts[String(line[range]).lowercased()] {
            return .counted(count)
        }
        if let regex = labeledRoundHeaderRegex, firstMatch(regex, in: line) != nil {
            return .labeled
        }
        return nil
    }

    // MARK: - Spec parsing

    private enum BValue: Equatable {
        case reps(Int)
        case duration(Int)
        case distance(Double, DistanceUnit)
        /// "3xAMRAP" / "2xfailure" — a set count with no rep target.
        case toFailure
    }

    private struct AxB {
        var a: Double
        var b: BValue
        var embeddedWeight: (Double, WeightUnit)?
    }

    private static func parseSpec(
        _ rawTokens: [String],
        defaultWeightUnit: WeightUnit
    ) -> [ParsedSetDraft] {
        var axbs: [AxB] = []
        var weight: (value: Double, unit: WeightUnit)?
        var distance: (value: Double, unit: DistanceUnit)?
        var standaloneDuration: Int?
        var repRange: Int?
        var repLadder: RepLadder?
        var wordReps: Int?
        var bareNumbers: [Double] = []
        var expectWeight = false

        // Pull rest and RPE out first so "90s rest" isn't a timed set, "RPE 8"
        // isn't a bare 8 lb, and tempo "31x1" isn't a second pair.
        let (restStripped, restSeconds) = extractRest(mergeSpecTokens(rawTokens))
        let (rpeStripped, difficulty) = extractRPE(restStripped)
        let tokens = stripTempo(rpeStripped)

        for token in tokens {
            let lower = token.lowercased()

            // Intensity percentages ("85%", "85-90%") are noise — never a load,
            // rep count, or bare number.
            if lower.hasSuffix("%") { continue }

            if lower == "@" { expectWeight = true; continue }

            if expectWeight {
                expectWeight = false
                // A number right after "@" is the load, with or without an explicit unit.
                if let w = parseWeight(lower) ?? Double(lower).map({ ($0, defaultWeightUnit) }) {
                    weight = weight ?? w
                    continue
                }
                // not a weight after all — fall through to normal classification
            }

            if lower.hasPrefix("@") {
                let rest = String(lower.dropFirst())
                if let w = parseWeight(rest) ?? Double(rest).map({ ($0, defaultWeightUnit) }) {
                    weight = weight ?? w
                    continue
                }
            }
            // Rep ladders ("225x5/3/1", "3x10-8-6", "5/3/1") before AxB: the
            // rung list makes them more than a single sets×reps token.
            if let ladder = parseRepLadder(lower, defaultWeightUnit: defaultWeightUnit) {
                repLadder = repLadder ?? ladder
                continue
            }
            if let axb = parseAxB(lower, defaultWeightUnit: defaultWeightUnit) {
                axbs.append(axb)
                continue
            }
            // An x-prefixed number is a rep count whose "x" lost its partner to
            // spacing ("60 kg x 10" → "60kg", "x10").
            if lower.hasPrefix("x"), lower.count > 1,
               let reps = Double(lower.dropFirst()), reps > 0 {
                bareNumbers.append(reps)
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
            repLadder: repLadder,
            wordReps: wordReps,
            bareNumbers: bareNumbers,
            defaultWeightUnit: defaultWeightUnit
        )
        return annotate(sets, restSeconds: restSeconds, difficulty: difficulty)
    }

    private static func annotate(
        _ sets: [ParsedSetDraft],
        restSeconds: Int?,
        difficulty: Int?
    ) -> [ParsedSetDraft] {
        guard restSeconds != nil || difficulty != nil else { return sets }
        return sets.map { set in
            var updated = set
            if updated.restSeconds == nil { updated.restSeconds = restSeconds }
            if updated.difficulty == nil { updated.difficulty = difficulty }
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

    // MARK: - RPE notation

    /// Removes RPE tokens so they cannot be read as load. Safe patterns only:
    /// "RPE 8", "rpe8", "@RPE 8", "@RPE 8.5". Bare "@ 8" stays weight.
    private static func extractRPE(_ tokens: [String]) -> (tokens: [String], difficulty: Int?) {
        var remaining = tokens
        for (index, token) in remaining.enumerated() {
            if let value = rpeFromGluedToken(token.lowercased()) {
                remaining.remove(at: index)
                return (remaining, value)
            }
        }
        guard let markerIndex = remaining.firstIndex(where: { isRPEMarker($0) }) else {
            return (remaining, nil)
        }
        if markerIndex + 1 < remaining.count,
           let value = CSVNumber.rpe(remaining[markerIndex + 1]) {
            remaining.removeSubrange(markerIndex...(markerIndex + 1))
            return (remaining, value)
        }
        if markerIndex > 0, let value = CSVNumber.rpe(remaining[markerIndex - 1]) {
            remaining.removeSubrange((markerIndex - 1)...markerIndex)
            return (remaining, value)
        }
        remaining.remove(at: markerIndex)
        return (remaining, nil)
    }

    private static func rpeFromGluedToken(_ lower: String) -> Int? {
        var body = lower
        if body.hasPrefix("@") { body.removeFirst() }
        guard body.hasPrefix("rpe"), body.count > 3 else { return nil }
        body = String(body.dropFirst(3))
        if body.hasPrefix("@") { body.removeFirst() }
        return CSVNumber.rpe(body)
    }

    /// `rpe` and `@rpe` (spaced `@RPE 8`). Trailing punctuation from OCR is ignored.
    private static func isRPEMarker(_ token: String) -> Bool {
        var body = token.lowercased()
        while let last = body.last, !last.isLetter { body.removeLast() }
        while let first = body.first, first != "@", !first.isLetter { body.removeFirst() }
        if body.hasPrefix("@") { body.removeFirst() }
        return body == "rpe"
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

    // MARK: - Tempo notation

    /// A tempo prescription token: digits and x/- separators only, with at
    /// least one separator ("31x1", "3-0-1", "4-1-2-0"). This shape also
    /// matches a real weight×reps pair ("135x5"), so it is only ever applied
    /// behind the "tempo" keyword or inside parentheses — never bare.
    private static let tempoRegex = try? NSRegularExpression(
        pattern: #"^(?=.*[x-])\d[\dx-]*\d$"#
    )

    private static func isTempoLike(_ token: String) -> Bool {
        var body = token
        if body.hasPrefix("("), body.hasSuffix(")") {
            body = String(body.dropFirst().dropLast())
        }
        guard let regex = tempoRegex else { return false }
        return regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
    }

    /// Removes tempo notation from the merged spec tokens. Conservative on
    /// purpose: a token is only stripped when the "tempo" keyword precedes it
    /// ("tempo 31x1", "tempo 3-0-1") or it is parenthesized AND looks like
    /// tempo ("(31x1)") — so a real "135x5" weight×reps pair is never eaten.
    private static func stripTempo(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            let lower = tokens[index].lowercased()
            if lower == "tempo" {
                // The tempo value itself follows the keyword; drop both when it
                // looks like tempo, just the keyword otherwise.
                if index + 1 < tokens.count, isTempoLike(tokens[index + 1].lowercased()) {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if lower.hasPrefix("("), lower.hasSuffix(")"), isTempoLike(lower) {
                index += 1
                continue
            }
            result.append(tokens[index])
            index += 1
        }
        return result
    }

    private static func buildSets(
        axbs: [AxB],
        weight: (value: Double, unit: WeightUnit)?,
        distance: (value: Double, unit: DistanceUnit)?,
        standaloneDuration: Int?,
        repRange: Int?,
        repLadder: RepLadder?,
        wordReps: Int?,
        bareNumbers: [Double],
        defaultWeightUnit: WeightUnit
    ) -> [ParsedSetDraft] {
        // A rep ladder is the most specific shape on the line: one set per rung.
        // Weight comes from the ladder token itself ("225x5/3/1"), an explicit
        // load ("Squat 5/3/1 @ 225"), or a single trailing bare number.
        if let repLadder {
            let resolvedWeight = repLadder.weight ?? weight.map { ($0.value, $0.unit) }
                ?? (bareNumbers.count == 1 ? (bareNumbers[0], defaultWeightUnit) : nil)
            return repLadder.rungs.map {
                ParsedSetDraft(weight: resolvedWeight?.0, weightUnit: resolvedWeight?.1 ?? defaultWeightUnit, reps: $0)
            }
        }

        if axbs.count == 1 {
            let axb = axbs[0]
            // "315x5" — A is the load, not a set count.
            if axb.a >= weightDisambiguationThreshold, case let .reps(reps) = axb.b, axb.embeddedWeight == nil {
                return [ParsedSetDraft(weight: axb.a, weightUnit: weight?.unit ?? defaultWeightUnit, reps: reps)]
            }

            // Sets × reps (or sets × per-set duration).
            let count = max(1, Int(axb.a))
            let resolvedWeight = axb.embeddedWeight ?? weight.map { ($0.value, $0.unit) }
                ?? trailingWeight(from: bareNumbers, hasDuration: { if case .duration = axb.b { return true } else { return false } }(), defaultWeightUnit: defaultWeightUnit)
            let template: ParsedSetDraft
            switch axb.b {
            case .reps(let reps):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? defaultWeightUnit,
                    reps: reps
                )
            case .duration(let seconds):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? defaultWeightUnit,
                    durationSeconds: seconds
                )
            case .distance(let value, let unit):
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? defaultWeightUnit,
                    distance: value,
                    distanceUnit: unit
                )
            case .toFailure:
                // AMRAP / to-failure sets: count known, rep target deliberately nil —
                // the review screen fills it in.
                template = ParsedSetDraft(
                    weight: resolvedWeight?.0,
                    weightUnit: resolvedWeight?.1 ?? defaultWeightUnit
                )
            }
            return Array(repeating: template, count: count).map { var s = $0; s.id = UUID(); return s }
        }

        if axbs.count >= 2 {
            // Weight × reps pairs: "135x5 155x3 175x1".
            return axbs.compactMap { axb in
                guard case let .reps(reps) = axb.b else { return nil }
                return ParsedSetDraft(weight: axb.a, weightUnit: weight?.unit ?? defaultWeightUnit, reps: reps)
            }
        }

        // No `AxB` — cardio, timed, or a single bare value.
        if distance != nil || standaloneDuration != nil {
            return [ParsedSetDraft(
                weight: weight?.value,
                weightUnit: weight?.unit ?? defaultWeightUnit,
                distance: distance?.value,
                distanceUnit: distance?.unit ?? .meters,
                durationSeconds: standaloneDuration
            )]
        }
        if bareNumbers.count == 1 {
            let bare = bareNumbers[0]
            // "225 … for a double" — the bare number is the load, the word the reps.
            if let wordReps {
                return [ParsedSetDraft(weight: bare, weightUnit: weight?.unit ?? defaultWeightUnit, reps: wordReps)]
            }
            // A lone big number is a load ("Bench 225"), a small one a rep
            // count ("Pushups 20") — same threshold as the AxB disambiguation.
            if weight == nil, bare >= weightDisambiguationThreshold {
                return [ParsedSetDraft(weight: bare, weightUnit: defaultWeightUnit)]
            }
            if let reps = intIfWhole(bare) {
                return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? defaultWeightUnit, reps: reps)]
            }
        }
        // A lone rep range ("Curls 8-10") — the lower bound is the target.
        if let repRange {
            return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? defaultWeightUnit, reps: repRange)]
        }
        // A rep word with an explicit load ("Bench 225lb for a double") or alone.
        if let wordReps {
            return [ParsedSetDraft(weight: weight?.value, weightUnit: weight?.unit ?? defaultWeightUnit, reps: wordReps)]
        }
        if let weight {
            return [ParsedSetDraft(weight: weight.value, weightUnit: weight.unit)]
        }
        return []
    }

    /// A single trailing bare number after a sets×reps token is read as the load
    /// ("Squat 5x5 225"). Skipped when the set already carries a duration.
    private static func trailingWeight(
        from bareNumbers: [Double],
        hasDuration: Bool,
        defaultWeightUnit: WeightUnit
    ) -> (Double, WeightUnit)? {
        guard !hasDuration, bareNumbers.count == 1 else { return nil }
        return (bareNumbers[0], defaultWeightUnit)
    }

    // MARK: - Token parsers

    /// A rep ladder / pyramid token: "225x5/3/1" (weight × rungs), "3x10-8-6"
    /// (leading count × dash rungs), or a bare "5/3/1". The rungs are the
    /// ground truth — one set each — so a leading count that disagrees with
    /// the rung count is ignored in the rungs' favor.
    private struct RepLadder {
        var rungs: [Int]
        /// Set only when the leading number reads as a load ("225x5/3/1") —
        /// a small leading count ("1x5/3/1") is not a weight.
        var weight: (Double, WeightUnit)?
    }

    private static func parseRepLadder(_ token: String, defaultWeightUnit: WeightUnit) -> RepLadder? {
        var body = token
        var leading: Double?
        if let xIndex = token.firstIndex(of: "x") {
            guard let a = Double(token[..<xIndex]), a > 0 else { return nil }
            leading = a
            body = String(token[token.index(after: xIndex)...])
            // A second "x" is embedded-weight notation ("5x5x225"), not a ladder.
            guard !body.contains("x") else { return nil }
        }
        let separator: Character = body.contains("/") ? "/" : "-"
        let parts = body.split(separator: separator, omittingEmptySubsequences: false)
        // 3+ rungs required: a 2-part slash token is a date ("8/12") and a
        // 2-part dash token is a rep range ("8-10") — both have owners already.
        guard parts.count >= 3 else { return nil }
        var rungs: [Int] = []
        for part in parts {
            guard let rep = intIfWhole(Double(part)), rep > 0 else { return nil }
            rungs.append(rep)
        }
        var weight: (Double, WeightUnit)?
        if let leading, leading >= weightDisambiguationThreshold {
            weight = (leading, defaultWeightUnit)
        }
        return RepLadder(rungs: rungs, weight: weight)
    }

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

    private static func parseAxB(_ token: String, defaultWeightUnit: WeightUnit) -> AxB? {
        guard token.contains("x") else { return nil }
        let parts = token.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let a = Double(parts[0]), a > 0 else { return nil }
        guard let b = parseBValue(parts[1]) else { return nil }
        var embedded: (Double, WeightUnit)?
        if parts.count == 3 {
            embedded = parseWeight(parts[2]) ?? Double(parts[2]).map { ($0, defaultWeightUnit) }
        }
        return AxB(a: a, b: b, embeddedWeight: embedded)
    }

    private static func parseBValue(_ s: String) -> BValue? {
        if s == "amrap" || s == "failure" { return .toFailure }
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
    /// Exposed so the model-backed parser can use the same deterministic rules.
    static func explicitDate(in text: String, referenceDate: Date) -> Date? {
        HandwrittenWorkoutDateParser.explicitDate(in: text, referenceDate: referenceDate)
    }

    /// True when `rawLine` is a session-boundary date header with no leftover
    /// exercise notation.
    static func isSessionDateHeader(_ rawLine: String, referenceDate: Date) -> Bool {
        HandwrittenWorkoutDateParser.isSessionDateHeader(rawLine, referenceDate: referenceDate)
    }

    /// Date headers plus numbered session labels (`Day 1`, `Session 2: Legs`).
    static func isSessionSplitHeader(_ rawLine: String, referenceDate: Date) -> Bool {
        HandwrittenWorkoutDateParser.isSessionSplitHeader(rawLine, referenceDate: referenceDate)
    }

    static func isNumberedSessionHeader(_ rawLine: String) -> Bool {
        HandwrittenWorkoutDateParser.isNumberedSessionHeader(rawLine)
    }

    static func numberedSessionHeaderRemainder(_ rawLine: String) -> String? {
        HandwrittenWorkoutDateParser.numberedSessionHeaderRemainder(rawLine)
    }

    private static func detectRelativeDate(
        in line: String,
        referenceDate: Date
    ) -> HandwrittenWorkoutDateParser.Match? {
        HandwrittenWorkoutDateParser.detectRelativeDate(in: line, referenceDate: referenceDate)
    }

    private static func detectDate(
        in line: String,
        referenceDate: Date
    ) -> HandwrittenWorkoutDateParser.Match? {
        HandwrittenWorkoutDateParser.detectDate(in: line, referenceDate: referenceDate)
    }

    // MARK: - Helpers

    private static func firstMatch(
        _ regex: NSRegularExpression,
        in line: String
    ) -> NSTextCheckingResult? {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static func normalize(_ line: String) -> String {
        HandwrittenWorkoutText.normalize(line)
    }

    private static func isSpecStart(_ token: String) -> Bool {
        if token == "@" || token.hasPrefix("@") { return true }
        return token.contains(where: \.isNumber)
    }

    private static func isWordOnly(_ line: String) -> Bool {
        HandwrittenWorkoutText.isWordOnly(line)
    }

    private static func cleanName(_ name: String) -> String {
        HandwrittenWorkoutText.cleanName(name)
    }

    private static func promotedExerciseName(_ line: String) -> String {
        HandwrittenWorkoutText.promotedExerciseName(line)
    }

    private static func cleanTitle(_ line: String) -> String {
        HandwrittenWorkoutText.cleanTitle(line)
    }

    private static func isWeekday(_ line: String) -> Bool {
        HandwrittenWorkoutText.isWeekday(line)
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
