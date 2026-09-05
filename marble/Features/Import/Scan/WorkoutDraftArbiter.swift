import Foundation

/// Picks between the deterministic notation parse and the on-device model parse of
/// the same source text. The model reads prose the notation parser can't, but it
/// can also collapse set counts and invent numbers. The notation parser gives
/// stable readings of supported formats, but can misread unfamiliar prose. Scoring both
/// drafts against the source text lets the more faithful one win instead of
/// blindly preferring whichever the model produced.
nonisolated enum WorkoutDraftArbiter {

    /// Picks the more faithful draft and merges cross-cutting fields.
    static func choose(
        deterministic: ParsedWorkoutDraft,
        model: ParsedWorkoutDraft?,
        sourceText: String
    ) -> ParsedWorkoutDraft {
        choose(deterministic: deterministic, candidates: [model], sourceText: sourceText)
    }

    /// Multi-candidate form: the deterministic draft competes against any number of
    /// model-derived drafts (structured extraction, notation rewrite, …). Highest
    /// fidelity wins; ties prefer the earliest contender, with the deterministic
    /// draft first, preserving a stable interpretation when fidelity is tied.
    static func choose(
        deterministic: ParsedWorkoutDraft,
        candidates: [ParsedWorkoutDraft?],
        sourceText: String
    ) -> ParsedWorkoutDraft {
        let contenders = candidates.compactMap { $0 }.map { candidate in
            var grounded = candidate
            var seenMovements: Set<String> = []
            grounded.exercises = candidate.exercises.compactMap { proposed in
                let metrics = proposed.sets.map { set in
                    "\(set.weight ?? -1):\(set.weightUnit):\(set.reps ?? -1):\(set.distance ?? -1):\(set.distanceUnit):\(set.durationSeconds ?? -1):\(set.restSeconds ?? -1)"
                }.joined(separator: "|")
                guard seenMovements.insert(movementKey(proposed.name) + ":" + metrics).inserted else { return nil }
                guard let source = sourceSpan(for: proposed.name, in: sourceText),
                      !requiresIntentReview(source.text) else { return nil }
                let exercise = fillingKnownOmissions(proposed, source: source.text)
                // A number belonging only to another movement or the date cannot
                // justify a model claim. Unsupported claims stay in source text
                // for review rather than becoming fabricated journal metrics.
                let local = numberTokens(in: source.text)
                let values = numericValues(in: ParsedWorkoutDraft(exercises: [exercise]))
                let faithful = agreesWithKnownMetrics(exercise, source: source.text)
                    && values.exact.allSatisfy { local.contains($0) }
                    && values.seconds.allSatisfy { value in
                        let variants: Set<Double> = [value, value / 60, value / 3600]
                        return !variants.isDisjoint(with: local)
                    }
                return faithful ? exercise : nil
            }
            return grounded
        }.filter(\.hasContent)
        guard !contenders.isEmpty else { return deterministic }

        // The deterministic draft leads the field when it has content, so an equal
        // score never displaces it; among model drafts, earlier candidates win ties.
        var field = contenders
        if deterministic.hasContent { field.insert(deterministic, at: 0) }

        var winner = field[0]
        var winnerScore = score(winner, against: sourceText)
        for contender in field.dropFirst() {
            let contenderScore = score(contender, against: sourceText)
            if contenderScore > winnerScore {
                winner = contender
                winnerScore = contenderScore
            }
        }
        for loser in [deterministic] + contenders where loser != winner {
            winner = merge(winner: winner, loser: loser)
        }
        // Lexical anchoring cannot distinguish repeated occurrences of a name
        // (Squat / Bench / Squat), or multiple movements on one source line.
        // Never reorder or overwrite a trusted deterministic sequence in that
        // situation. Unresolved source stays available for explicit review.
        let originalNames = deterministic.importableExercises.map { movementKey($0.name) }
        if Set(originalNames).count < originalNames.count { return deterministic }
        let winnerNames = winner.importableExercises.map { movementKey($0.name) }
        if Set(winnerNames).count < winnerNames.count {
            return deterministic.hasContent ? deterministic : winner
        }

        // A partial but grounded candidate can recover a movement absent from
        // the winning draft. Do not duplicate or replace a source block here.
        for candidate in contenders {
            for exercise in candidate.importableExercises {
                guard sourceSpan(for: exercise.name, in: sourceText) != nil,
                      !winner.exercises.contains(where: {
                          movementKey($0.name) == movementKey(exercise.name)
                      }) else { continue }
                winner.exercises.append(exercise)
            }
        }
        // Whole-note selection must not erase independently recognized movements.
        // Restore deterministic rows when their source-local interpretation is at
        // least as faithful, retaining notes, dates, and review metadata too.
        for exercise in deterministic.importableExercises {
            guard let source = sourceSpan(for: exercise.name, in: sourceText) else { continue }
            if let index = winner.exercises.firstIndex(where: {
                movementKey($0.name) == movementKey(exercise.name)
            }) {
                let original = ParsedWorkoutDraft(exercises: [exercise])
                let selected = ParsedWorkoutDraft(exercises: [winner.exercises[index]])
                if score(original, against: source.text) >= score(selected, against: source.text) {
                    winner.exercises[index] = exercise
                }
            } else {
                winner.exercises.append(exercise)
            }
        }
        winner.exercises = winner.exercises.enumerated().sorted { lhs, rhs in
            let left = sourceSpan(for: lhs.element.name, in: sourceText)?.index ?? Int.max
            let right = sourceSpan(for: rhs.element.name, in: sourceText)?.index ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        return winner
    }

    /// Fidelity score of a draft against the source text (internal, exposed for tests).
    static func score(_ draft: ParsedWorkoutDraft, against sourceText: String) -> Double {
        // Presence: reward recognizing more of the note, but cap it so a draft
        // can't win on exercise count alone while getting the numbers wrong.
        // Distinct names only — splitting "Bench 135x5 155x3" into three "Bench"
        // exercises is fragmentation, not coverage, and must not score higher.
        let distinctNames = Set(draft.importableExercises.map {
            $0.trimmedName.lowercased()
        })
        let presence = min(2.0, Double(distinctNames.count) * 0.5)

        // Set-count agreement: explicit NxM tokens are the strongest signal in the
        // text; a draft that collapses "3x8" into one set should lose here.
        let agreement: Double
        if let expected = expectedSetCount(in: sourceText), expected > 0 {
            agreement = max(0, 1 - Double(abs(draft.totalSetCount - expected)) / Double(expected))
        } else {
            agreement = 0.5 // no notation to check against — neutral
        }

        // Numeric fidelity: every value the draft claims should trace back to a
        // number in the text; invented values drag this down. Durations and rest
        // are seconds internally but written in minutes or hours, so they match
        // through those conversions too — a correct "in 25 minutes" → 1500 must
        // not score worse than a wrong verbatim 25.
        let (exactValues, secondsValues) = numericValues(in: draft)
        let tokens = numberTokens(in: sourceText)
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
        // A draft should also *explain* the text's numbers: set counts, values, and
        // second-values (matching through minute/hour conversion) all count, as do
        // the resolved date's components.
        let coverage: Double
        if tokens.isEmpty {
            coverage = 0.5 // nothing to explain — neutral
        } else {
            var claimed = Set(exactValues)
            for exercise in draft.importableExercises {
                claimed.insert(Double(exercise.sets.count))
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

        // Global numeric coverage is only a secondary signal: penalize claims
        // using numbers found on a different movement's line.
        let localPenalty = draft.importableExercises.reduce(0.0) { penalty, exercise in
            guard let span = sourceSpan(for: exercise.name, in: sourceText) else { return penalty + 4 }
            let local = numberTokens(in: span.text)
            let values = numericValues(in: ParsedWorkoutDraft(exercises: [exercise]))
            let misplaced = values.exact.filter { tokens.contains($0) && !local.contains($0) }.count
            let expected = expectedSetCount(in: span.text)
            let countPenalty = expected.map { $0 == exercise.sets.count ? 0.0 : 2.0 } ?? 0
            return penalty + min(4, Double(misplaced)) + countPenalty
        }
        return presence + 3 * agreement + 3 * fidelity + 2 * coverage - localPenalty
    }

    /// Total sets implied by explicit NxM notation tokens in the text, nil when none.
    static func expectedSetCount(in sourceText: String) -> Int? {
        guard let regex = setsByRepsRegex else { return nil }
        let text = normalize(sourceText)
        var total = 0
        var found = false
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text),
                  let sets = Int(text[range]) else { continue }
            // Below the threshold the first number is a set count; at or above it
            // it's a load ("315x5"), mirroring HandwrittenWorkoutParser's rule.
            guard Double(sets) < weightDisambiguationThreshold else { continue }
            total += sets
            found = true
        }
        if !found, let countRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})\s+sets?\b"#, options: .caseInsensitive) {
            for match in countRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), let count = Int(text[range]), count > 0 {
                    total += count
                    found = true
                }
            }
        }
        return found ? total : nil
    }

    private static func movementKey(_ name: String) -> String {
        let ignored: Set<String> = ["barbell", "dumbbell", "kettlebell", "db", "bb", "kb", "press", "meter", "metre", "fifty", "twenty", "hundred"]
        return name.lowercased().split(whereSeparator: { !$0.isLetter }).map { token in
            var word = String(token)
            if ["ran", "running"].contains(word) { return "run" }
            if word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") { word.removeLast() }
            return word
        }.filter { !ignored.contains($0) }.joined(separator: " ")
    }

    /// Conservative lexical anchoring: equipment expansion is allowed, but a
    /// model must still name a movement actually present in this source segment.
    /// Split sentences at explicit transitions, not commas (which carry metrics).
    static func sourceSpan(for name: String, in text: String) -> (index: Int, text: String)? {
        let normalizedText = text.replacingOccurrences(of: #"(?i)[;\n]|(?<=[a-z])\.\s+|,?\s+(?:then|followed by)\s+"#, with: "\n", options: .regularExpression)
        let lines = normalizedText.components(separatedBy: .newlines)
        let ignored: Set<String> = ["barbell", "dumbbell", "kettlebell", "db", "bb", "kb", "press"]
        func words(_ value: String) -> Set<String> {
            Set(value.lowercased().split(whereSeparator: { !$0.isLetter }).map { word in
                var word = String(word)
                if ["ran", "running"].contains(word) { word = "run" }
                if word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") { word.removeLast() }
                return word
            })
        }
        let allNameWords = words(name)
        let anchors = allNameWords.subtracting(ignored)
        let required = anchors.isEmpty ? allNameWords : anchors
        guard !required.isEmpty else { return nil }
        let matches = lines.enumerated().compactMap { index, line -> (Int, String, Int)? in
            let overlap = required.intersection(words(line)).count
            guard overlap > 0, overlap * 2 >= required.count else { return nil }
            return (index, line, overlap)
        }
        guard let best = matches.max(by: { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            let leftExtra = words(lhs.1).subtracting(allNameWords).count
            let rightExtra = words(rhs.1).subtracting(allNameWords).count
            return leftExtra == rightExtra ? lhs.0 > rhs.0 : leftExtra > rightExtra
        }) else { return nil }
        // Include numeric continuation rows under a standalone movement heading.
        var source = best.1
        var next = best.0 + 1
        while next < lines.count {
            let line = lines[next].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { next += 1; continue }
            guard line.first?.isNumber == true || line.lowercased().hasPrefix("set ") || line.lowercased().hasPrefix("rest ") else { break }
            source += "\n" + line
            next += 1
        }
        return (best.0, source)
    }

    /// The model may recognize a movement while omitting a metric. Fill only
    /// explicit facts from a complete local parse with the exact same set count;
    /// contradictory model values remain intact for the validator to reject.
    private static func fillingKnownOmissions(_ proposed: ParsedExerciseDraft, source: String) -> ParsedExerciseDraft {
        let reading = HandwrittenWorkoutParser.parseDetailed(
            source, referenceDate: Date(timeIntervalSince1970: 0),
            defaultWeightUnit: proposed.sets.first?.weightUnit ?? .lb
        )
        guard reading.droppedLines.isEmpty, reading.draft.importableExercises.count == 1,
              let known = reading.draft.importableExercises.first,
              known.sets.count == proposed.sets.count else { return proposed }
        var result = proposed
        for index in result.sets.indices {
            let fact = known.sets[index]
            if result.sets[index].weight == nil { result.sets[index].weight = fact.weight; result.sets[index].weightUnit = fact.weightUnit }
            if result.sets[index].reps == nil { result.sets[index].reps = fact.reps }
            if result.sets[index].distance == nil { result.sets[index].distance = fact.distance; result.sets[index].distanceUnit = fact.distanceUnit }
            if result.sets[index].durationSeconds == nil { result.sets[index].durationSeconds = fact.durationSeconds }
            if result.sets[index].restSeconds == nil { result.sets[index].restSeconds = fact.restSeconds }
        }
        return result
    }

    /// When notation supplies typed facts, number membership is insufficient:
    /// "20 minutes" is not 20 pounds and "2 sets" is not two repetitions.
    private static func agreesWithKnownMetrics(_ exercise: ParsedExerciseDraft, source: String) -> Bool {
        let reading = HandwrittenWorkoutParser.parseDetailed(
            source, referenceDate: Date(timeIntervalSince1970: 0),
            defaultWeightUnit: exercise.sets.first?.weightUnit ?? .lb
        )
        guard reading.droppedLines.isEmpty, reading.draft.importableExercises.count == 1,
              let known = reading.draft.importableExercises.first else { return true }
        return exercise.sets.allSatisfy { claimed in
            known.sets.contains { fact in
                (claimed.weight == nil || (claimed.weight == fact.weight && claimed.weightUnit == fact.weightUnit))
                    && (claimed.reps == nil || claimed.reps == fact.reps)
                    && (claimed.distance == nil || (claimed.distance == fact.distance && claimed.distanceUnit == fact.distanceUnit))
                    && (claimed.durationSeconds == nil || claimed.durationSeconds == fact.durationSeconds)
                    && (claimed.restSeconds == nil || claimed.restSeconds == fact.restSeconds)
                    && (claimed.difficulty == nil || claimed.difficulty == fact.difficulty)
            }
        }
    }

    /// A model must not turn planned, skipped, or contradicted activity into
    /// completed sets merely because its numbers are present in the source.
    private static func requiresIntentReview(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\b(skip(?:ped)?|didn't|did not|not done|planned|tomorrow|instead|actually|correction|scratch that|total|altogether)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// A name substring alone cannot clear an unresolved-source warning.
    static func isSourceLineRepresented(
        _ line: String, by draft: ParsedWorkoutDraft, referenceDate: Date,
        defaultWeightUnit: WeightUnit
    ) -> Bool {
        guard !requiresIntentReview(line) else { return false }
        let reading = HandwrittenWorkoutParser.parseDetailed(
            line, referenceDate: referenceDate, defaultWeightUnit: defaultWeightUnit
        )
        guard reading.droppedLines.isEmpty, reading.draft.hasContent else { return false }
        return reading.draft.importableExercises.allSatisfy { expected in
            draft.importableExercises.contains { actual in
                guard actual.trimmedName.caseInsensitiveCompare(expected.trimmedName) == .orderedSame,
                      actual.sets.count == expected.sets.count else { return false }
                return zip(actual.sets, expected.sets).allSatisfy { lhs, rhs in
                    lhs.weight == rhs.weight && lhs.weightUnit == rhs.weightUnit
                        && lhs.reps == rhs.reps && lhs.distance == rhs.distance
                        && lhs.distanceUnit == rhs.distanceUnit
                        && lhs.durationSeconds == rhs.durationSeconds
                        && lhs.restSeconds == rhs.restSeconds
                        && lhs.difficulty == rhs.difficulty && lhs.notes == rhs.notes
                }
            }
        }
    }

    // MARK: - Merging

    private static let placeholderTitles: Set<String> = ["Scanned workout", "Typed workout", "Imported workout"]

    /// Carries fields the winner missed but the loser caught: the losing parse may
    /// still have read the date header or title line correctly even when its sets
    /// were worse.
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
        return merged
    }

    // MARK: - Scoring helpers

    /// Same sets-vs-weight cutoff as HandwrittenWorkoutParser: real set counts
    /// almost never reach 25, real loads almost always do.
    private static let weightDisambiguationThreshold: Double = 25

    private static let setsByRepsRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})\s*x\s*(\d+(?:\.\d+)?)"#
    )

    private static let numberTokenRegex = try? NSRegularExpression(
        pattern: #"\d+(?:\.\d+)?"#
    )

    /// Split into exact-match values and seconds-denominated values (which also
    /// match through minute/hour conversion).
    private static func numericValues(in draft: ParsedWorkoutDraft) -> (exact: [Double], seconds: [Double]) {
        var exact: [Double] = []
        var seconds: [Double] = []
        for exercise in draft.importableExercises {
            for set in exercise.sets {
                if let weight = set.weight { exact.append(weight) }
                if let reps = set.reps { exact.append(Double(reps)) }
                if let difficulty = set.difficulty { exact.append(Double(difficulty)) }
                if let distance = set.distance { exact.append(distance) }
                if let duration = set.durationSeconds { seconds.append(Double(duration)) }
                if let rest = set.restSeconds { seconds.append(Double(rest)) }
            }
        }
        return (exact, seconds)
    }

    /// Spelled numbers count as present in the text — a draft that correctly read
    /// "three sets of eight" must not lose fidelity because 3 and 8 aren't digits.
    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90,
        "single": 1, "double": 2, "triple": 3
    ]

    private static let colonDurationRegex = try? NSRegularExpression(
        pattern: #"\b(\d+):(\d{2})(?::(\d{2}))?\b"#
    )

    /// All numbers in the text as Doubles so "185" matches a weight of 185.0.
    /// Colon durations also contribute their value in seconds ("1:30" → 90), so a
    /// draft that correctly resolved them isn't scored as inventing numbers.
    private static func numberTokens(in sourceText: String) -> Set<Double> {
        guard let regex = numberTokenRegex else { return [] }
        let matches = regex.matches(in: sourceText, range: NSRange(sourceText.startIndex..., in: sourceText))
        var tokens = Set(matches.compactMap { match in
            Range(match.range, in: sourceText).flatMap { Double(sourceText[$0]) }
        })
        for word in sourceText.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let value = numberWords[String(word)] { tokens.insert(value) }
        }
        // Spoken loads: "one eighty five", "one hundred and eighty five",
        // and "twenty five". Keep these within contiguous number-word spans.
        let words = sourceText.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        var run: [String] = []
        func flush() {
            defer { run.removeAll() }
            let values = run.compactMap { numberWords[$0] }
            guard values.count > 1 else { return }
            if let hundred = run.firstIndex(of: "hundred"), hundred > 0,
               let leading = numberWords[run[hundred - 1]] {
                tokens.insert(leading * 100 + run.dropFirst(hundred + 1).compactMap { numberWords[$0] }.reduce(0, +))
            } else if values.count >= 2, values[0] < 10, values[1] >= 20 {
                tokens.insert(values[0] * 100 + values.dropFirst().reduce(0, +))
            } else {
                tokens.insert(values.reduce(0, +))
            }
        }
        for word in words {
            if numberWords[word] != nil || word == "hundred" || (word == "and" && !run.isEmpty) {
                run.append(word)
            } else { flush() }
        }
        flush()
        if let colonRegex = colonDurationRegex {
            for match in colonRegex.matches(in: sourceText, range: NSRange(sourceText.startIndex..., in: sourceText)) {
                let groups = (1...3).map { index -> Int? in
                    guard match.range(at: index).location != NSNotFound,
                          let range = Range(match.range(at: index), in: sourceText) else { return nil }
                    return Int(sourceText[range])
                }
                if let first = groups[0], let second = groups[1] {
                    if let third = groups[2] {
                        tokens.insert(Double(first * 3600 + second * 60 + third))
                    } else {
                        tokens.insert(Double(first * 60 + second))
                    }
                }
            }
        }
        return tokens
    }

    /// Same multiplication-sign normalization as HandwrittenWorkoutParser, so "3×8"
    /// and "3x8" imply the same set count.
    private static func normalize(_ text: String) -> String {
        var result = text
        for multiply in ["×", "✕", "✗", "*", "·"] {
            result = result.replacingOccurrences(of: multiply, with: "x")
        }
        return result
    }
}
