import Foundation

/// Picks between the deterministic notation parse and the on-device model parse of
/// the same source text. The model reads prose the notation parser can't, but it
/// also collapses set counts and invents numbers; the notation parser never
/// hallucinates but goes empty on anything that isn't gym shorthand. Scoring both
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
    /// draft first — it never hallucinates, so at equal fidelity it is the safer
    /// draft to put in front of the user.
    static func choose(
        deterministic: ParsedWorkoutDraft,
        candidates: [ParsedWorkoutDraft?],
        sourceText: String
    ) -> ParsedWorkoutDraft {
        let contenders = candidates.compactMap { $0 }.filter(\.hasContent)
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
        let fidelity: Double
        if exactValues.isEmpty && secondsValues.isEmpty {
            fidelity = 0.5 // nothing to verify — neutral
        } else {
            let tokens = numberTokens(in: sourceText)
            var matched = exactValues.filter { tokens.contains($0) }.count
            matched += secondsValues.filter { seconds in
                tokens.contains(seconds) || tokens.contains(seconds / 60) || tokens.contains(seconds / 3600)
            }.count
            fidelity = Double(matched) / Double(exactValues.count + secondsValues.count)
        }

        return presence + 3 * agreement + 3 * fidelity
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
        return found ? total : nil
    }

    // MARK: - Merging

    private static let placeholderTitles: Set<String> = ["Scanned workout", "Typed workout"]

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
        "single": 1, "double": 2, "triple": 3
    ]

    /// All numbers in the text as Doubles so "185" matches a weight of 185.0.
    private static func numberTokens(in sourceText: String) -> Set<Double> {
        guard let regex = numberTokenRegex else { return [] }
        let matches = regex.matches(in: sourceText, range: NSRange(sourceText.startIndex..., in: sourceText))
        var tokens = Set(matches.compactMap { match in
            Range(match.range, in: sourceText).flatMap { Double(sourceText[$0]) }
        })
        for word in sourceText.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let value = numberWords[String(word)] { tokens.insert(value) }
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
