import Foundation

/// The person's answer to "Was this read correctly?" on a model-interpreted
/// review. Only aggregate counts are kept, on this device; nothing about the
/// workout is stored or sent. Sharing an example is a separate, explicit
/// action through the system share sheet.
nonisolated enum ModelReadVerdict: String, Equatable, Sendable, Codable {
    case correct
    case incorrect
}

/// Aggregate thumbs-up / thumbs-down counts in user defaults.
struct ModelReadFeedbackStore {
    static let correctCountKey = "modelReadFeedback.correctCount"
    static let incorrectCountKey = "modelReadFeedback.incorrectCount"

    let defaults: UserDefaults

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults
    }

    func count(_ verdict: ModelReadVerdict) -> Int {
        defaults.integer(forKey: Self.key(for: verdict))
    }

    func record(_ verdict: ModelReadVerdict) {
        defaults.set(count(verdict) + 1, forKey: Self.key(for: verdict))
    }

    private static func key(for verdict: ModelReadVerdict) -> String {
        verdict == .correct ? correctCountKey : incorrectCountKey
    }
}

/// Plain-text example a person can choose to share after a misread: what they
/// wrote and what Marble read. Built only when they tap Share.
nonisolated enum ModelReadExample {
    static func shareText(source: String, draft: ParsedWorkoutDraft, modelName: String) -> String {
        var lines = [
            "Marble misread this workout (on-device Apple Intelligence, \(modelName)).",
            "",
            "What I wrote:",
            source.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "What Marble read:",
        ]
        let exercises = draft.importableExercises
        if exercises.isEmpty {
            lines.append("(no exercises)")
        }
        for exercise in exercises {
            lines.append("- \(exercise.trimmedName): \(setSummary(exercise.sets))")
        }
        return lines.joined(separator: "\n")
    }

    /// "3 sets of 8 reps @ 185 lb" when every set matches; otherwise each set
    /// in order, so a misread per-set value is visible.
    static func setSummary(_ sets: [ParsedSetDraft]) -> String {
        let descriptions = sets.map(describe)
        guard let first = descriptions.first else { return "no sets" }
        let count = sets.count
        if descriptions.allSatisfy({ $0 == first }) {
            let noun = count == 1 ? "set" : "sets"
            return first.isEmpty ? "\(count) \(noun)" : "\(count) \(noun) of \(first)"
        }
        return descriptions.map { $0.isEmpty ? "set" : $0 }.joined(separator: "; ")
    }

    static func describe(_ set: ParsedSetDraft) -> String {
        var parts: [String] = []
        if let reps = set.reps { parts.append("\(reps) rep\(reps == 1 ? "" : "s")") }
        if let distance = set.distance { parts.append("\(number(distance)) \(set.distanceUnit.symbol)") }
        if let duration = set.durationSeconds { parts.append("\(duration) s") }
        var text = parts.joined(separator: ", ")
        if let weight = set.weight {
            text += text.isEmpty ? "\(number(weight)) \(set.weightUnit.symbol)" : " @ \(number(weight)) \(set.weightUnit.symbol)"
        }
        if let rest = set.restSeconds { text += text.isEmpty ? "rest \(rest) s" : ", rest \(rest) s" }
        return text
    }

    /// Locale-independent so the example reads the same wherever it's pasted.
    private static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e9 { return String(Int(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
