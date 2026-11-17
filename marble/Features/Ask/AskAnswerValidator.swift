import Foundation

/// The gate between the on-device model and the Ask sheet. Same doctrine as
/// `InsightValidator` (and built on it): a sentence survives only if every
/// number it states appears in the tool outputs the engine produced, and it
/// stays clear of advice, health, diet and injury talk. Ask adds a few
/// question-answering hazards on top — recommendations, hedged estimates,
/// emoji, links — and keeps answers to at most two sentences.
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
        return InsightValidator.numbersAreGrounded(sentence, in: allowed)
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
