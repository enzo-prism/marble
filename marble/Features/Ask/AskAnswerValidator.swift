import Foundation

/// The gate between the on-device model and the Ask sheet. Same doctrine as
/// `InsightValidator` (whose number parsing and blocklist it reuses), but
/// stricter on numbers: Ask never rounds, so a stated number must equal a
/// tool-output value *exactly as displayed* — same value and same precision
/// ("14.8s" stays 14.8, never "15"; "102.5 kg" never "103") — and every
/// number word ("one", "twenty-five", "a dozen", "twice") must name a value
/// the tool outputs state. It also blocks advice, health, diet and injury
/// talk, hedged estimates, emoji and links, and keeps at most two sentences.
/// `TrainingInsights` keeps its own, more lenient rule.
nonisolated enum AskAnswerValidator {
    static let maximumSentences = 2
    static let maximumCharacters = 320

    /// Lowercased substrings that turn a factual answer into advice or
    /// speculation. Checked in addition to `InsightValidator.blocklist`.
    static let extraBlocklist: [String] = [
        "should", "recommend", "suggest", "consider ", "advice", "advise", "try to", "aim for",
        "health", "heart rate", "approximately", "roughly", "estimate", "probably", "i think",
        "http", "www.", "deload", "form cue", "warm up", "warm-up", "stretch"
    ]

    /// The answer to show, or nil when it can't be trusted and the
    /// deterministic sentence should ship instead. The first sentence must
    /// pass; a second is kept only when it passes too.
    static func validated(_ raw: String, facts: String, unit: WeightUnit) -> String? {
        let cleaned = clean(raw)
        guard !cleaned.isEmpty, !facts.isEmpty else { return nil }
        let allowed = InsightValidator.quantities(in: facts)
        let sentences = splitSentences(cleaned)
        guard let first = sentences.first, passes(first, allowed: allowed, unit: unit) else { return nil }
        var kept = [first]
        if sentences.count > 1, passes(sentences[1], allowed: allowed, unit: unit) {
            kept.append(sentences[1])
        }
        let answer = kept.joined(separator: " ")
        guard answer.count <= maximumCharacters else {
            return first.count <= maximumCharacters ? first : nil
        }
        return answer
    }

    static func passes(_ sentence: String, allowed: [InsightValidator.Quantity], unit: WeightUnit) -> Bool {
        guard !sentence.isEmpty, !containsEmoji(sentence) else { return false }
        if InsightValidator.isBlocked(sentence, unit: unit) { return false }
        let lowered = sentence.lowercased()
        if extraBlocklist.contains(where: { lowered.contains($0) }) { return false }
        return numbersAreExact(sentence, in: allowed)
    }

    /// True when every number in `sentence` — digits or words — is one of the
    /// fact values, at exactly its displayed precision.
    static func numbersAreExact(_ sentence: String, in facts: [InsightValidator.Quantity]) -> Bool {
        let claims = InsightValidator.quantities(in: sentence) + spelledQuantities(in: sentence)
        return claims.allSatisfy { claim in facts.contains { isSame(claim, $0) } }
    }

    static func isSame(_ claim: InsightValidator.Quantity, _ fact: InsightValidator.Quantity) -> Bool {
        let valueTolerance = 1e-9 * max(1, abs(fact.value))
        let precisionTolerance = 1e-9 * max(1, fact.precision)
        return abs(claim.value - fact.value) <= valueTolerance && abs(claim.precision - fact.precision) <= precisionTolerance
    }

    private static let units: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]
    /// Words that state a count without digits.
    private static let multiplicative: [String: Double] = [
        "once": 1, "single": 1, "twice": 2, "couple": 2, "double": 2, "thrice": 3, "triple": 3,
        "dozen": 12, "dozens": 12, "hundred": 100, "hundreds": 100, "thousand": 1000, "thousands": 1000
    ]

    /// Number words as quantities (precision 1). Tens followed by a unit word
    /// ("twenty-five", "twenty five") read as one number.
    static func spelledQuantities(in text: String) -> [InsightValidator.Quantity] {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        var found: [InsightValidator.Quantity] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if let ten = tens[word] {
                if index + 1 < words.count, let unit = units[words[index + 1]], unit >= 1, unit <= 9 {
                    found.append(.init(value: ten + unit, precision: 1))
                    index += 2
                    continue
                }
                found.append(.init(value: ten, precision: 1))
            } else if let value = units[word] ?? multiplicative[word] {
                found.append(.init(value: value, precision: 1))
            }
            index += 1
        }
        return found
    }

    /// Strips markdown emphasis, surrounding quotes and stray whitespace.
    static func clean(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = CharacterSet(charactersIn: "\"“”'")
        text = text.trimmingCharacters(in: quotes).trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text
    }

    /// Splits on sentence-ending punctuation followed by whitespace, so
    /// decimals ("102.5 kg") and times ("14.8s") stay whole.
    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let isEnd = ".!?".contains(character)
            let nextIsSpace = index + 1 >= characters.count || characters[index + 1].isWhitespace
            if isEnd, nextIsSpace {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    private static func containsEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }
    }
}
