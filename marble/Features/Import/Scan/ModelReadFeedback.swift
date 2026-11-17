import CoreTransferable
import Foundation
import UniformTypeIdentifiers

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

/// What the model read, frozen when review opens — before the person edits
/// anything. A shared example must show the misreading, not the fix.
nonisolated struct ModelReadSnapshot: Equatable, Sendable {
    var source: String
    /// The draft exactly as the parse returned it.
    var reading: ParsedWorkoutDraft
    var modelName: String
}

/// The share-sheet payload after a thumbs-down. Holds values only; the text
/// is built when the share sheet exports it, not on every render.
nonisolated struct ModelReadShareItem: Transferable, Sendable {
    var snapshot: ModelReadSnapshot
    /// The review as it stands, shown as corrections when it differs.
    var current: ParsedWorkoutDraft

    var text: String {
        ModelReadExample.shareText(
            source: snapshot.source, reading: snapshot.reading,
            corrected: current, modelName: snapshot.modelName
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
    }
}

/// Plain-text example a person can choose to share after a misread: what they
/// wrote, what Marble read, and — if they fixed it in review — what it should
/// have been.
nonisolated enum ModelReadExample {
    static func shareText(
        source: String,
        reading: ParsedWorkoutDraft,
        corrected: ParsedWorkoutDraft? = nil,
        modelName: String
    ) -> String {
        var lines = [
            "Marble misread this workout (on-device Apple Intelligence, \(modelName)).",
            "",
            "What I wrote:",
            source.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "What Marble read:",
        ]
        let read = exerciseLines(reading)
        lines += read
        if let corrected {
            let fixed = exerciseLines(corrected)
            if fixed != read {
                lines += ["", "Corrected to:"] + fixed
            }
        }
        return lines.joined(separator: "\n")
    }

    static func exerciseLines(_ draft: ParsedWorkoutDraft) -> [String] {
        let exercises = draft.importableExercises
        guard !exercises.isEmpty else { return ["(no exercises)"] }
        return exercises.map { "- \($0.trimmedName): \(setSummary($0.sets))" }
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
