import Foundation

/// Picks between the deterministic notation parse and the on-device model parse of
/// the same source text. The model reads prose the notation parser can't, but it
/// also collapses set counts, invents numbers and exercises, and guesses units;
/// the notation parser never hallucinates but goes empty on anything that isn't
/// gym shorthand. Scoring both drafts against the source text lets the more
/// faithful one win instead of blindly preferring whichever the model produced.
nonisolated enum WorkoutDraftArbiter {

    /// Picks the more faithful draft and merges cross-cutting fields.
    static func choose(
        deterministic: ParsedWorkoutDraft,
        model: ParsedWorkoutDraft?,
        sourceText: String,
        defaultWeightUnit: WeightUnit = .lb
    ) -> ParsedWorkoutDraft {
        choose(
            deterministic: deterministic,
            candidates: [model],
            sourceText: sourceText,
            defaultWeightUnit: defaultWeightUnit
        )
    }

    /// Multi-candidate form: the deterministic draft competes against any number of
    /// model-derived drafts (structured extraction, notation rewrite, …). Highest
    /// fidelity wins; ties prefer the earliest contender, with the deterministic
    /// draft first — it never hallucinates, so at equal fidelity it is the safer
    /// draft to put in front of the user. A winning model draft comes back with
    /// `interpretedByModel` set so review can say the text was interpreted.
    /// `defaultWeightUnit` is the unit the user logs in, assumed wherever the
    /// text writes no unit.
    static func choose(
        deterministic: ParsedWorkoutDraft,
        candidates: [ParsedWorkoutDraft?],
        sourceText: String,
        defaultWeightUnit: WeightUnit = .lb
    ) -> ParsedWorkoutDraft {
        let contenders = candidates.compactMap { $0 }.filter(\.hasContent)
        guard !contenders.isEmpty else { return deterministic }

        // The deterministic draft leads the field when it has content, so an equal
        // score never displaces it; among model drafts, earlier candidates win ties.
        // Positions, not equality, identify the winner: a model draft can be
        // value-identical to the deterministic one and must not claim provenance.
        var field: [(draft: ParsedWorkoutDraft, isModel: Bool)] = contenders.map { ($0, true) }
        if deterministic.hasContent { field.insert((deterministic, false), at: 0) }

        let context = SourceContext(sourceText, defaultWeightUnit: defaultWeightUnit)
        var winnerIndex = 0
        var winnerScore = score(field[0].draft, context: context)
        for index in field.indices.dropFirst() {
            let contenderScore = score(field[index].draft, context: context)
            if contenderScore > winnerScore {
                winnerIndex = index
                winnerScore = contenderScore
            }
        }

        var winner = field[winnerIndex].draft
        var losers = field.indices.filter { $0 != winnerIndex }.map { field[$0].draft }
        if !deterministic.hasContent { losers.insert(deterministic, at: 0) }
        for loser in losers {
            winner = merge(winner: winner, loser: loser)
        }
        if field[winnerIndex].isModel { winner.interpretedByModel = true }
        // A model can label an unstated unit "lb" despite the user's kg
        // preference. Scoring only penalizes that guess; it does not prevent
        // it from winning. With no source unit anywhere, the default is the
        // authoritative unit, not a request to convert the numeric load.
        if !context.hasExplicitWeightUnit {
            for exerciseIndex in winner.exercises.indices {
                for setIndex in winner.exercises[exerciseIndex].sets.indices
                    where winner.exercises[exerciseIndex].sets[setIndex].weight != nil {
                    winner.exercises[exerciseIndex].sets[setIndex].weightUnit = defaultWeightUnit
                }
            }
        }
        return winner
    }

    /// Fidelity score of a draft against the source text (internal, exposed for tests).
    static func score(
        _ draft: ParsedWorkoutDraft,
        against sourceText: String,
        defaultWeightUnit: WeightUnit = .lb
    ) -> Double {
        score(draft, context: SourceContext(sourceText, defaultWeightUnit: defaultWeightUnit))
    }

    private static func score(_ draft: ParsedWorkoutDraft, context: SourceContext) -> Double {
        let exercises = draft.importableExercises

        // Grounding: every exercise name should trace back to words in the text.
        // A model that turns "shoulders felt tight" into a Shoulder Press set is
        // inventing an exercise, and reusing the written numbers must not let it
        // score higher than the draft that left the aside alone.
        var groundedNames: Set<String> = []
        var ungroundedNames: Set<String> = []
        for exercise in exercises {
            let key = exercise.trimmedName.lowercased()
            if context.grounds(exerciseName: exercise.trimmedName) {
                groundedNames.insert(key)
            } else {
                ungroundedNames.insert(key)
            }
        }

        // Presence: reward recognizing more of the note, but cap it so a draft
        // can't win on exercise count alone while getting the numbers wrong.
        // Distinct grounded names only — splitting "Bench 135x5 155x3" into three
        // "Bench" exercises is fragmentation, not coverage, and must not score higher.
        let presence = min(2.0, Double(groundedNames.count) * 0.5)
        let ungroundedPenalty = min(2.0, Double(ungroundedNames.count) * 0.75)

        // Set-count agreement: NxM tokens and spelled-out counts ("three sets of
        // ten") are the strongest signal in the text. A shortfall is fully
        // penalized — a draft that collapses "3x8" into one set should lose here —
        // but a surplus only lightly: sets read out of prose the patterns don't
        // recognize must not lose to a draft that skipped that prose.
        let agreement: Double
        if let expected = context.expectedSetCount, expected > 0 {
            let total = draft.totalSetCount
            let shortfall = Double(max(0, expected - total)) / Double(expected)
            let surplus = Double(max(0, total - expected)) / Double(expected)
            agreement = max(0, 1 - shortfall - 0.25 * surplus)
        } else {
            agreement = 0.5 // no set counts to check against — neutral
        }

        // Invented repeats: identical sets repeated k times need the text to say
        // so — a k in set-count position, or the values written k times. "Bench 185
        // for 8" read as three sets is padding, even when a stray "Week 3" makes
        // the count look plausible.
        var unbackedRepeats = 0
        for exercise in exercises {
            for (values, count) in identicalSetGroups(exercise) where count > 1 {
                let written = values.map { context.occurrences(of: $0) }.max() ?? 0
                if !context.setCountEvidence.contains(Double(count)) && written < count {
                    unbackedRepeats += count - 1
                }
            }
        }
        let repeatPenalty = 0.5 * min(1, Double(unbackedRepeats) / Double(max(1, draft.totalSetCount)))

        // Numeric fidelity: every value the draft claims should trace back to a
        // number in the text; invented values drag this down. Values count once per
        // exercise, so a set repeated five times can't outvote one invented value.
        // Durations and rest are seconds internally but written in minutes or
        // hours, so they match through those conversions too — a correct "in 25
        // minutes" → 1500 must not score worse than a wrong verbatim 25.
        let (exactValues, secondsValues) = numericValues(in: draft)
        let tokens = context.tokens
        let fidelity: Double
        if exactValues.isEmpty && secondsValues.isEmpty {
            fidelity = 0.5 // nothing to verify — neutral
        } else {
            var matched = exactValues.filter { tokens.contains($0) }.count
            matched += secondsValues.filter { seconds in
                tokens.contains(seconds) || tokens.contains(seconds / 60) || tokens.contains(seconds / 3600)
            }.count
            fidelity = Double(matched) / Double(exactValues.count + secondsValues.count)
        }

        // Coverage: precision alone lets a draft win by claiming only the numbers
        // it is sure of ("20 minute plank" while ignoring "3 planks of 45 seconds").
        // A draft should also *explain* the text's numbers: values, second-values
        // (matching through minute/hour conversion) and the resolved date's
        // components count. Set counts count only against numbers the text puts in
        // set-count position, so an invented count can't "explain" a "Week 3" header.
        let coverage: Double
        if tokens.isEmpty {
            coverage = 0.5 // nothing to explain — neutral
        } else {
            var claimed = Set(exactValues)
            for exercise in exercises {
                let setCount = Double(exercise.sets.count)
                if context.setCountEvidence.contains(setCount) { claimed.insert(setCount) }
            }
            for seconds in secondsValues {
                claimed.insert(seconds)
                claimed.insert(seconds / 60)
                claimed.insert(seconds / 3600)
            }
            if let performedAt = draft.performedAt {
                let components = Calendar.current.dateComponents([.year, .month, .day], from: performedAt)
                for value in [components.year, components.month, components.day].compactMap({ $0 }) {
                    claimed.insert(Double(value))
                    claimed.insert(Double(value % 100)) // "‘26" style two-digit years
                }
            }
            let covered = tokens.filter { claimed.contains($0) }.count
            coverage = Double(covered) / Double(tokens.count)
        }

        let unitPenalty = unitMismatchPenalty(draft, context: context)

        return presence + 3 * agreement + 3 * fidelity + 2 * coverage
            - ungroundedPenalty - repeatPenalty - unitPenalty
    }

    /// Total sets the text states, nil when it states none: explicit NxM tokens
    /// plus spelled-out counts ("three sets of ten", "5 sets"). Per line the larger
    /// of the two is taken, so "3x8, 3 sets" isn't counted twice.
    static func expectedSetCount(in sourceText: String) -> Int? {
        SourceContext.setCounts(in: sourceText).expected
    }

    // MARK: - Merging

    private static let placeholderTitles: Set<String> = ["Scanned workout", "Typed workout", "Imported workout"]

    /// Carries fields the winner missed but the loser caught: the losing parse may
    /// still have read the date header, title line, workout note, or a set's RPE
    /// correctly even when its sets were worse.
    private static func merge(
        winner: ParsedWorkoutDraft,
        loser: ParsedWorkoutDraft
    ) -> ParsedWorkoutDraft {
        var merged = winner
        if merged.performedAt == nil, let loserDate = loser.performedAt {
            merged.performedAt = loserDate
        }
        if placeholderTitles.contains(merged.title), !placeholderTitles.contains(loser.title) {
            merged.title = loser.title
        }
        if isBlank(merged.notes), !isBlank(loser.notes) {
            merged.notes = loser.notes
        }
        // RPE only moves between sets that are provably the same set: same
        // exercise position, matching names, same set index.
        for index in merged.exercises.indices where index < loser.exercises.count {
            let loserExercise = loser.exercises[index]
            guard namesMatch(merged.exercises[index].trimmedName, loserExercise.trimmedName) else { continue }
            for setIndex in merged.exercises[index].sets.indices where setIndex < loserExercise.sets.count {
                if merged.exercises[index].sets[setIndex].difficulty == nil,
                   let difficulty = loserExercise.sets[setIndex].difficulty {
                    merged.exercises[index].sets[setIndex].difficulty = difficulty
                }
            }
        }
        return merged
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "Bench" and "Barbell Bench Press" name the same exercise; "Bench" and
    /// "Squat" don't. One name's expanded letters containing the other's is enough.
    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = nameWords(lhs).joined()
        let right = nameWords(rhs).joined()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    // MARK: - Scoring helpers

    /// Same sets-vs-weight cutoff as HandwrittenWorkoutParser: real set counts
    /// almost never reach 25, real loads almost always do.
    private static let weightDisambiguationThreshold: Double = 25

    /// Values per exercise, deduplicated, split into exact-match values and
    /// seconds-denominated values (which also match through minute/hour conversion).
    private static func numericValues(in draft: ParsedWorkoutDraft) -> (exact: [Double], seconds: [Double]) {
        var exact: [Double] = []
        var seconds: [Double] = []
        for exercise in draft.importableExercises {
            var exerciseExact: Set<Double> = []
            var exerciseSeconds: Set<Double> = []
            for set in exercise.sets {
                if let weight = set.weight { exerciseExact.insert(weight) }
                if let reps = set.reps { exerciseExact.insert(Double(reps)) }
                if let distance = set.distance { exerciseExact.insert(distance) }
                if let duration = set.durationSeconds { exerciseSeconds.insert(Double(duration)) }
                if let rest = set.restSeconds { exerciseSeconds.insert(Double(rest)) }
            }
            exact.append(contentsOf: exerciseExact)
            seconds.append(contentsOf: exerciseSeconds)
        }
        return (exact, seconds)
    }

    /// Runs of value-identical sets within an exercise, keyed by the values a
    /// reader would look for in the text (weight, reps, distance, duration).
    private static func identicalSetGroups(_ exercise: ParsedExerciseDraft) -> [(values: [Double], count: Int)] {
        var counts: [[Double]: Int] = [:]
        var order: [[Double]] = []
        for set in exercise.sets {
            var values: [Double] = []
            if let weight = set.weight { values.append(weight) }
            if let reps = set.reps { values.append(Double(reps)) }
            if let distance = set.distance { values.append(distance) }
            if let duration = set.durationSeconds {
                values.append(Double(duration))
                if duration % 60 == 0 { values.append(Double(duration / 60)) }
            }
            guard !values.isEmpty else { continue }
            if counts[values] == nil { order.append(values) }
            counts[values, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    /// Weight units must agree with the text: a unit written next to the number
    /// ("100kg") makes the other unit a hard contradiction; otherwise the one unit
    /// the whole note uses, or else the user's default, is a soft preference.
    /// Averaged over each exercise's distinct loads.
    private static func unitMismatchPenalty(_ draft: ParsedWorkoutDraft, context: SourceContext) -> Double {
        var checked = 0
        var penalty = 0.0
        for exercise in draft.importableExercises {
            var seen: Set<String> = []
            for set in exercise.sets {
                guard let weight = set.weight,
                      seen.insert("\(weight)\(set.weightUnit.rawValue)").inserted else { continue }
                checked += 1
                if let written = context.writtenUnits[weight], written.count == 1 {
                    if !written.contains(set.weightUnit) { penalty += 1.5 }
                } else if set.weightUnit != (context.documentUnit ?? context.defaultWeightUnit) {
                    penalty += 0.5
                }
            }
        }
        return checked == 0 ? 0 : penalty / Double(checked)
    }

    // MARK: - Exercise-name grounding

    /// Shorthand expanded on both sides, so "DB press" grounds "Dumbbell Press"
    /// and "RDL" grounds "Romanian Deadlift". Irregular past tenses map to the
    /// verb a model names the exercise after ("ran" → "Run").
    private static let wordExpansions: [String: [String]] = [
        "db": ["dumbbell"], "dbs": ["dumbbell"],
        "bb": ["barbell"], "kb": ["kettlebell"], "kbs": ["kettlebell"],
        "ohp": ["overhead", "press"], "rdl": ["romanian", "deadlift"], "rdls": ["romanian", "deadlift"],
        "sldl": ["stiff", "leg", "deadlift"], "dl": ["deadlift"], "dls": ["deadlift"],
        "ran": ["run"], "swam": ["swim"], "rode": ["ride"]
    ]

    /// Equipment and posture words a model adds to a name the note left bare
    /// ("Squat" → "Barbell Back Squat"); their absence from the text proves nothing.
    private static let optionalNameWords: Set<String> = [
        "barbell", "dumbbell", "kettlebell", "machine", "cable", "smith", "flat", "back",
        "standing", "seated", "conventional", "exercise", "weighted", "bodyweight",
        "the", "and", "with"
    ]

    /// Heads whose "press" goes unwritten ("bench" → "Bench Press"). Deliberately
    /// not "shoulder": "shoulders felt tight" must not ground a Shoulder Press.
    private static let impliedPressHeads: Set<String> = [
        "bench", "leg", "chest", "incline", "decline", "floor"
    ]

    /// Lowercased, abbreviation-expanded, plural-stripped words of a text.
    private static func nameWords(_ text: String) -> [String] {
        expandedWords(text).map(stem)
    }

    private static func expandedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .flatMap { word -> [String] in
                let word = String(word)
                return wordExpansions[word] ?? [word]
            }
    }

    /// Plural stripping only — enough for "squats", "presses", "lunges".
    private static func stem(_ word: String) -> String {
        guard word.count > 3 else { return word }
        for suffix in ["sses", "shes", "ches", "xes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }

    /// Edit distance counting an adjacent swap as one edit (optimal string
    /// alignment), for OCR slips ("Bnech") the model rightly corrected.
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var beforePrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], beforePrevious[j - 2] + 1)
                }
            }
            beforePrevious = previous
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Source analysis

    /// Everything the score reads off the source text, computed once per choice.
    private struct SourceContext {
        let defaultWeightUnit: WeightUnit
        /// Separate from documentUnit: nil there can also mean mixed units.
        let hasExplicitWeightUnit: Bool
        /// Numbers the text states — digits, number words, colon durations in
        /// seconds, and articles standing in for 1 ("a mile").
        let tokens: Set<Double>
        /// How often each number is written, for backing repeated identical sets.
        let tokenCounts: [Double: Int]
        /// Numbers in set-count position (NxM leads, "N sets", AxBxN tails, EMOM minutes).
        let setCountEvidence: Set<Double>
        let expectedSetCount: Int?
        /// Units written directly after a number ("100kg", "185 lbs").
        let writtenUnits: [Double: Set<WeightUnit>]
        /// The only weight unit the note mentions anywhere, when it mentions one.
        let documentUnit: WeightUnit?
        let sourceWords: [String]
        let compactSource: String

        init(_ sourceText: String, defaultWeightUnit: WeightUnit) {
            self.defaultWeightUnit = defaultWeightUnit
            let text = Self.normalize(sourceText)
            let counts = Self.numberCounts(in: text)
            self.tokens = Set(counts.keys)
            self.tokenCounts = counts
            let setCounts = Self.setCounts(in: sourceText)
            self.setCountEvidence = setCounts.evidence
            self.expectedSetCount = setCounts.expected
            self.writtenUnits = Self.writtenUnits(in: text)
            let mentionsKg = Self.matchCount(Self.kgWordRegex, in: text) > 0
            let mentionsLb = Self.matchCount(Self.lbWordRegex, in: text) > 0
            self.hasExplicitWeightUnit = mentionsKg || mentionsLb || sourceText.contains("#")
                || Self.matchCount(Self.unitBeforeMultiplicationRegex, in: text) > 0
            self.documentUnit = mentionsKg == mentionsLb ? nil : (mentionsKg ? .kg : .lb)
            let words = WorkoutDraftArbiter.expandedWords(text)
            self.sourceWords = words.map(WorkoutDraftArbiter.stem)
            self.compactSource = words.joined()
        }

        func occurrences(of value: Double) -> Int { tokenCounts[value] ?? 0 }

        /// True when every meaningful word of the name appears in the text —
        /// verbatim, inside a longer word ("pullups" ⊃ "pull"), or one OCR slip
        /// away. Optional equipment words and a press implied by its head
        /// ("Bench" → "Bench Press") may be missing.
        func grounds(exerciseName name: String) -> Bool {
            let words = WorkoutDraftArbiter.nameWords(name)
            guard !words.isEmpty else { return false }
            if compactSource.contains(words.joined()) { return true }
            let impliesPress = words.contains { WorkoutDraftArbiter.impliedPressHeads.contains($0) }
            let required = words.filter { word in
                word.count >= 3
                    && !WorkoutDraftArbiter.optionalNameWords.contains(word)
                    && !(word == "press" && impliesPress)
            }
            return required.allSatisfy { word in
                if compactSource.contains(word) { return true }
                let limit = word.count >= 7 ? 2 : (word.count >= 4 ? 1 : 0)
                guard limit > 0 else { return false }
                return sourceWords.contains {
                    abs($0.count - word.count) <= limit && WorkoutDraftArbiter.editDistance(word, $0) <= limit
                }
            }
        }

        // MARK: Patterns

        /// Multiplication signs to "x" (as HandwrittenWorkoutParser does) and
        /// digit-grouping commas dropped with HandwrittenWorkoutText.normalize's
        /// rule: a standalone 1–2 digit group plus one 3-digit group is a thousands
        /// separator ("1,025" → 1025), while load lists ("185,205") stay two numbers.
        static func normalize(_ text: String) -> String {
            var result = text
            for multiply in ["×", "✕", "✗", "*", "·"] {
                result = result.replacingOccurrences(of: multiply, with: "x")
            }
            return result.replacingOccurrences(
                of: #"(?<![\d,xX])(?<![xX] )(\d{1,2}),(\d{3})(?![\dxX]|,\d)"#,
                with: "$1$2",
                options: .regularExpression
            )
        }

        private static let numberTokenRegex = try? NSRegularExpression(
            pattern: #"\d+(?:\.\d+)?"#
        )

        private static let colonDurationRegex = try? NSRegularExpression(
            pattern: #"\b(\d+):(\d{2})(?::(\d{2}))?\b"#
        )

        /// NxM with either case of x; the lead is a set count only below the
        /// weight-disambiguation threshold.
        private static let setsByRepsRegex = try? NSRegularExpression(
            pattern: #"(?<![\d.])(\d{1,2})\s*x\s*(\d+(?:\.\d+)?)"#,
            options: [.caseInsensitive]
        )

        /// "185x8x3" — the tail is the set count.
        private static let weightRepsSetsRegex = try? NSRegularExpression(
            pattern: #"(?<![\d.])\d+(?:\.\d+)?\s*x\s*\d+\s*x\s*(\d{1,2})(?![\d.])"#,
            options: [.caseInsensitive]
        )

        /// "EMOM 10 min", "10 min EMOM", "E2MOM x 8" — one set per interval.
        private static let emomRegex = try? NSRegularExpression(
            pattern: #"\be\d?mom\s*(?:x\s*|for\s*)?(\d{1,2})\b|\b(\d{1,2})\s*(?:min(?:ute)?s?|m)?\s*e\d?mom\b"#,
            options: [.caseInsensitive]
        )

        /// "three sets", "5 sets", "4 rounds", "a set of 10".
        private static let spelledSetsRegex = try? NSRegularExpression(
            pattern: #"(?<![\d.])\b(\d{1,2}|[a-z]+)\s+(?:sets?|rounds?)\b"#,
            options: [.caseInsensitive]
        )

        /// "a mile", "an hour", "a set of" — articles standing in for 1. Only
        /// before a unit or count word, so "felt a bit tight" states no number.
        private static let articleNumberRegex = try? NSRegularExpression(
            pattern: #"\b(?:a|an)\s+(?:miles?|mi|km|kilometers?|laps?|sets?|minutes?|mins?|hours?|hrs?|rounds?|reps?|plates?|meters?|yards?)\b"#,
            options: [.caseInsensitive]
        )

        private static let kgWordRegex = try? NSRegularExpression(
            pattern: #"(?<![a-z])(?:kgs?|kilos?|kilograms?)(?![a-z])"#,
            options: [.caseInsensitive]
        )

        private static let lbWordRegex = try? NSRegularExpression(
            pattern: #"(?<![a-z])(?:lbs?|pounds?)(?![a-z])"#,
            options: [.caseInsensitive]
        )

        /// "80kgx8" / "225lbs×5" still state a unit. The ordinary word
        /// boundary excludes the following x, so preserve this compact form too.
        private static let unitBeforeMultiplicationRegex = try? NSRegularExpression(
            pattern: #"(?<![a-z])(?:kgs?|kilos?|kilograms?|lbs?|pounds?)(?=x\s*\d)"#,
            options: [.caseInsensitive]
        )

        private static let unitAfterNumberRegex = try? NSRegularExpression(
            pattern: #"(?<![\d.])(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|lbs?|pounds?|#)(?![a-z])"#,
            options: [.caseInsensitive]
        )

        /// Spelled numbers count as present in the text — a draft that correctly
        /// read "three sets of eight" must not lose fidelity because 3 and 8 aren't digits.
        private static let numberWords: [String: Double] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
            "single": 1, "double": 2, "triple": 3
        ]

        private static func matchCount(_ regex: NSRegularExpression?, in text: String) -> Int {
            regex?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        }

        private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }

        /// Every number in the (normalized) text as a Double so "185" matches a
        /// weight of 185.0, with how often each is written. Colon durations also
        /// contribute their value in seconds ("1:30" → 90), so a draft that
        /// correctly resolved them isn't scored as inventing numbers.
        private static func numberCounts(in text: String) -> [Double: Int] {
            var counts: [Double: Int] = [:]
            let range = NSRange(text.startIndex..., in: text)
            for match in numberTokenRegex?.matches(in: text, range: range) ?? [] {
                if let value = group(match, 0, in: text).flatMap(Double.init) { counts[value, default: 0] += 1 }
            }
            for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                if let value = numberWords[String(word)] { counts[value, default: 0] += 1 }
            }
            for match in colonDurationRegex?.matches(in: text, range: range) ?? [] {
                let groups = (1...3).map { group(match, $0, in: text).flatMap { Int($0) } }
                if let first = groups[0], let second = groups[1] {
                    let seconds = groups[2].map { first * 3600 + second * 60 + $0 } ?? first * 60 + second
                    counts[Double(seconds), default: 0] += 1
                }
            }
            let articles = matchCount(articleNumberRegex, in: text)
            if articles > 0 { counts[1, default: 0] += articles }
            return counts
        }

        /// Set counts the text states, per line: the larger of the NxM sum and the
        /// spelled-out sum, so "3x8, 3 sets" counts three sets, not six.
        static func setCounts(in sourceText: String) -> (expected: Int?, evidence: Set<Double>) {
            var total = 0
            var found = false
            var evidence: Set<Double> = []
            for rawLine in normalize(sourceText).split(whereSeparator: \.isNewline) {
                let line = String(rawLine)
                let range = NSRange(line.startIndex..., in: line)
                var notation = 0
                var spelled = 0
                var lineFound = false
                for match in setsByRepsRegex?.matches(in: line, range: range) ?? [] {
                    // Below the threshold the first number is a set count; at or above
                    // it it's a load ("315x5"), mirroring HandwrittenWorkoutParser's rule.
                    guard let sets = group(match, 1, in: line).flatMap({ Int($0) }),
                          Double(sets) < weightDisambiguationThreshold else { continue }
                    notation += sets
                    lineFound = true
                    evidence.insert(Double(sets))
                }
                for match in spelledSetsRegex?.matches(in: line, range: range) ?? [] {
                    guard let raw = group(match, 1, in: line)?.lowercased() else { continue }
                    let value = Int(raw)
                        ?? numberWords[raw].map { Int($0) }
                        ?? (raw == "a" || raw == "an" ? 1 : nil)
                    guard let sets = value, sets > 0, Double(sets) < weightDisambiguationThreshold else { continue }
                    spelled += sets
                    lineFound = true
                    evidence.insert(Double(sets))
                }
                // Evidence only: these back a repeated set without adding to the
                // expected total, since the tail and interval readings are looser.
                for match in emomRegex?.matches(in: line, range: range) ?? [] {
                    if let sets = (group(match, 1, in: line) ?? group(match, 2, in: line)).flatMap({ Double($0) }) {
                        evidence.insert(sets)
                    }
                }
                for match in weightRepsSetsRegex?.matches(in: line, range: range) ?? [] {
                    if let sets = group(match, 1, in: line).flatMap({ Double($0) }),
                       sets < weightDisambiguationThreshold {
                        evidence.insert(sets)
                    }
                }
                if lineFound {
                    total += max(notation, spelled)
                    found = true
                }
            }
            return (found ? total : nil, evidence)
        }

        private static func writtenUnits(in text: String) -> [Double: Set<WeightUnit>] {
            var units: [Double: Set<WeightUnit>] = [:]
            let range = NSRange(text.startIndex..., in: text)
            for match in unitAfterNumberRegex?.matches(in: text, range: range) ?? [] {
                guard let value = group(match, 1, in: text).flatMap(Double.init),
                      let word = group(match, 2, in: text)?.lowercased() else { continue }
                units[value, default: []].insert(word.hasPrefix("k") ? .kg : .lb)
            }
            return units
        }
    }
}
