import Foundation

/// The notation-rewrite pass answers in plain text, not guided generation:
/// `SystemLanguageModel.Guardrails.permissiveContentTransformations` relaxes
/// guardrails only for *text* responses, so a `@Generable` rewrite still threw
/// guardrail violations on benign gym prose. This turns that text back into
/// the notation lines and date literal the deterministic pipeline consumes.
///
/// A small model adds formatting it was told not to (bullets, numbering, code
/// fences, "Here is the workout:"), so parsing is deliberately forgiving about
/// *shape* and strict about *content*: it only strips decoration and chatter,
/// never rewrites a line's words or numbers. Every surviving line still goes
/// through `HandwrittenWorkoutParser` and the arbiter's source grounding.
nonisolated struct ModelNotationOutput: Equatable, Sendable {
    /// The workout date exactly as the model copied it ("9/4/26",
    /// "yesterday"), or empty. Code resolves and grounds it, never the model.
    var dateText: String
    /// Notation lines in model order, decoration removed.
    var lines: [String]

    /// Bounds work on a runaway answer; far more than any real session.
    static let maximumLines = 80

    static func parse(_ raw: String) -> ModelNotationOutput {
        var dateText = ""
        var lines: [String] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            guard let line = cleaned(rawLine) else { continue }
            if let date = dateValue(in: line) {
                if dateText.isEmpty { dateText = date }
                continue
            }
            if isChatter(line) { continue }
            lines.append(line)
            if lines.count == maximumLines { break }
        }
        return ModelNotationOutput(dateText: dateText, lines: lines)
    }

    /// The lines a streamed snapshot has finished so far: everything before
    /// the last newline. The trailing fragment may still be growing, so it is
    /// withheld — the processing UI fills in a line at a time, not a token.
    static func completedLines(in partial: String) -> [String] {
        guard let lastNewline = partial.lastIndex(where: \.isNewline) else { return [] }
        return parse(String(partial[..<lastNewline])).lines
    }

    // MARK: - Line cleanup

    /// Leading list decoration: bullets, block quotes, markdown headings, and
    /// "1." / "1)" / "(1)" numbering. Numbering needs trailing whitespace so a
    /// line like "5x5 Squat" is never mistaken for a list index.
    private static let leadingDecoration = try? NSRegularExpression(
        pattern: #"^(?:[-*•·–—>#]+\s*|\(?\d{1,2}[.)]\s+)"#
    )
    private static let dateLine = try? NSRegularExpression(
        pattern: #"^(?i)date\s*[:：\-–—]\s*(.*)$"#
    )
    private static let trailingParenthetical = try? NSRegularExpression(
        pattern: #"\s*\([^)]*\)\s*$"#
    )
    /// Openers a model uses to talk about its answer instead of giving it.
    private static let chatterPrefixes = [
        "here is", "here's", "here are", "sure", "certainly", "of course", "okay", "ok,", "ok.",
        "below is", "this is", "these are", "the workout", "the log", "the notation", "your workout",
        "i converted", "i've", "i have", "i dropped", "i omitted", "i kept", "i ignored", "let me",
        "note:", "notes:", "notation:", "output:", "converted", "hope this", "let me know",
    ]
    private static let emptyDateValues: Set<String> = [
        "", "none", "n/a", "na", "unknown", "not stated", "not mentioned", "not given",
        "no date", "-", "—", "empty",
    ]

    /// Strips decoration from one raw line; nil when nothing is left or the
    /// line is a code-fence marker.
    static func cleaned(_ raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("```") else { return nil }
        line = line.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        // Decoration can stack ("- 1. Bench"); a few rounds is plenty.
        for _ in 0..<3 {
            guard let regex = leadingDecoration else { break }
            let range = NSRange(line.startIndex..., in: line)
            let stripped = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            if stripped == line { break }
            line = stripped
        }
        line = unquoted(line)
        // A line with no letters or digits ("---", "***") is a separator.
        guard line.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return line
    }

    /// `nil` when the line isn't a date line; otherwise the date literal,
    /// empty when the model wrote a placeholder like "none".
    static func dateValue(in line: String) -> String? {
        guard let regex = dateLine,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        var value = unquoted(String(line[range]).trimmingCharacters(in: .whitespaces))
        // "9/4/26 (as written)" — the parenthetical is commentary, and the
        // literal must match the source verbatim to be grounded.
        if let paren = trailingParenthetical {
            value = paren.stringByReplacingMatches(
                in: value, range: NSRange(value.startIndex..., in: value), withTemplate: ""
            )
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " .;,"))
        return emptyDateValues.contains(value.lowercased()) ? "" : value
    }

    static func isChatter(_ line: String) -> Bool {
        let lowered = line.lowercased()
        // A heading-like line ending in a colon ("Notation lines:", "Workout:")
        // introduces content rather than being content.
        if lowered.hasSuffix(":") { return true }
        return chatterPrefixes.contains { prefix in
            guard lowered.hasPrefix(prefix) else { return false }
            // Whole-word prefixes only: "sure" must not swallow "Surestep Lunge".
            guard let next = lowered.dropFirst(prefix.count).first else { return true }
            return !next.isLetter || prefix.last?.isLetter == false
        }
    }

    private static func unquoted(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in pairs where text.count >= 2 && text.first == open && text.last == close {
            return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
