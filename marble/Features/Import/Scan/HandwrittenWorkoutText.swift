import Foundation

/// Pure text normalization and naming rules shared by the deterministic workout
/// parser and its date/session-boundary parser.
nonisolated enum HandwrittenWorkoutText {
    static func normalize(_ line: String) -> String {
        var result = line
        for multiply in ["×", "✕", "✗", "*", "·"] {
            result = result.replacingOccurrences(of: multiply, with: "x")
        }
        for dash in ["–", "—"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        result = attachHyphenatedUnits(result)
        // Unspaced name/spec joins ("Squat5x5" → "Squat 5x5"). Lowercase letters
        // only, so superset tags like "A1:" keep their digit.
        result = result.replacingOccurrences(
            of: #"(?<=[a-z])(?=\d)"#,
            with: " ",
            options: .regularExpression
        )
        // "3x AMRAP" / "2x failure" — glue the target word to its set count so the
        // AxB tokenizer sees one token.
        result = result.replacingOccurrences(
            of: #"(?i)\b(\d+x)\s+(amrap|failure)\b"#,
            with: "$1$2",
            options: .regularExpression
        )
        // Digit-grouping commas are thousands separators ("1,025" → "1025"), never
        // token breaks — the generic comma→space rule below would silently turn
        // the load into 1.
        result = result.replacingOccurrences(
            of: #"(?<=\d),(?=\d{3}\b)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: ",", with: " ")
        let collapsed = result.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isWordOnly(_ line: String) -> Bool {
        guard line.contains(where: \.isLetter) else { return false }
        return !line.contains(where: \.isNumber) && !line.contains("@")
    }

    static func cleanName(_ name: String) -> String {
        var result = name.trimmingCharacters(
            in: CharacterSet(charactersIn: " :-–—•*").union(.whitespaces)
        )
        // Leading/trailing symbols that survive the trim — emoji bullets ("💪 Bench"),
        // stray punctuation — are never part of an exercise name.
        while let first = result.first, !(first.isLetter || first.isNumber) { result.removeFirst() }
        while let last = result.last, !(last.isLetter || last.isNumber) { result.removeLast() }
        return result
    }

    /// Strips an export header's "Exercise:" label and trailing equipment
    /// parenthetical ("Exercise: Bench Press (Barbell)" → "Bench Press").
    static func promotedExerciseName(_ line: String) -> String {
        var result = line
        if let range = result.range(
            of: #"^\s*exercise\s*:\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            result.removeSubrange(range)
        }
        if let range = result.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return cleanName(result)
    }

    static func cleanTitle(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(
            in: CharacterSet(charactersIn: " :-–—•").union(.whitespaces)
        )
        return trimmed.isEmpty ? "Scanned workout" : trimmed
    }

    static func isWeekday(_ line: String) -> Bool {
        weekdays.contains(line.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Drops a hyphen that glues a number to a unit word so the token reads as one
    /// unit ("20-meter" → "20meter"). Digit-digit and word-word hyphens survive.
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

    private static let weekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun"
    ]
}
