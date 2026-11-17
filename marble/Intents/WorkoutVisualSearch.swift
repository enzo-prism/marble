import AppIntents
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import VideoToolbox
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

// MARK: - Visual Intelligence: add a workout from what the camera or a screenshot sees
//
// When someone circles a whiteboard WOD, a program screenshot or a coach's message,
// Marble reads the pixels on device with its own recognizer and offers one result —
// "Review workout in Marble" — only when the deterministic parser finds workout
// notation. Opening it stages the text in the existing editable Add composer; nothing
// is saved until the person reviews it. No pixels or text leave the device.

/// Recognized workout text offered as a Visual Intelligence result.
///
/// The identifier *is* the recognized text (behind a version prefix), so the system
/// can hand the entity back to `OpenWorkoutCaptureIntent` after a relaunch without
/// Marble persisting anything it saw on screen.
nonisolated struct WorkoutCaptureEntity: AppEntity {
    static let identifierPrefix = "capture-v1:"
    /// Generous for a whiteboard or a program page; longer captures are trimmed at a
    /// line boundary and stay editable in review.
    static let maximumTextLength = 4_000

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Workout to Review", numericFormat: "\(placeholder: .int) workouts to review")
    }
    static var defaultQuery: WorkoutCaptureQuery { WorkoutCaptureQuery() }

    let id: String

    var text: String { String(id.dropFirst(Self.identifierPrefix.count)) }

    init(text: String) {
        id = Self.identifierPrefix + Self.bounded(text)
    }

    init?(id: String) {
        guard id.hasPrefix(Self.identifierPrefix), id.count > Self.identifierPrefix.count else { return nil }
        self.id = id
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Review workout in Marble",
            subtitle: "\(Self.preview(of: text))",
            image: .init(systemName: "square.and.pencil")
        )
    }

    /// The first few recognized lines, so the result shows what Marble read.
    static func preview(of text: String, lineLimit: Int = 3, characterLimit: Int = 90) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.prefix(lineLimit).joined(separator: " · ")
        let more = lines.count > lineLimit
        guard joined.count > characterLimit else { return more ? joined + " …" : joined }
        return String(joined.prefix(characterLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func bounded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumTextLength else { return trimmed }
        let prefix = trimmed.prefix(maximumTextLength)
        guard let lastBreak = prefix.lastIndex(where: \.isNewline) else { return String(prefix) }
        return String(prefix[..<lastBreak])
    }
}

nonisolated struct WorkoutCaptureQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WorkoutCaptureEntity] {
        identifiers.compactMap(WorkoutCaptureEntity.init(id:))
    }

    func suggestedEntities() async throws -> [WorkoutCaptureEntity] { [] }
}

/// Opens a Visual Intelligence result in the editable Add composer — the same
/// handoff as Review Workout Text. Never saves directly.
struct OpenWorkoutCaptureIntent: OpenIntent {
    static let title: LocalizedStringResource = "Review Captured Workout"
    static let description = IntentDescription("Opens workout text Marble read from the screen or camera for review. Nothing is logged until it is reviewed.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Workout") var target: WorkoutCaptureEntity

    init() {}
    init(target: WorkoutCaptureEntity) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.stageForReview(target.text)
        return .result()
    }

    /// The Review Workout Text handoff: the composer consumes the staged text on
    /// appear or on the notification, whichever comes first.
    @MainActor
    static func stageForReview(_ text: String, notify: Bool = true) {
        PendingTextImport.stage(text)
        if notify { NotificationCenter.default.post(name: .marbleOpenTextImport, object: nil) }
    }
}

nonisolated enum WorkoutVisualSearch {
    /// The single result for recognized text, or `nil` when it isn't a workout.
    static func result(forRecognizedText text: String, referenceDate: Date = Date()) -> WorkoutCaptureEntity? {
        guard isPlausibleWorkout(text, referenceDate: referenceDate) else { return nil }
        return WorkoutCaptureEntity(text: text)
    }

    /// Decided by the deterministic parser, never a model: the query must be fast
    /// and must stay silent for receipts, articles and chat that merely contain
    /// numbers.
    ///
    /// Plausible means the parser found at least one named movement with a real
    /// metric, and either the text carries explicit training notation ("3x8",
    /// "reps", "AMRAP", "EMOM", "RPE", "rounds"…), or several parsed sets come from
    /// text whose lines are mostly numeric, mostly claimed by the parser and not a
    /// price list.
    static func isPlausibleWorkout(_ text: String, referenceDate: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let parsed = HandwrittenWorkoutParser.parseDetailed(trimmed, referenceDate: referenceDate)
        let exercises = parsed.draft.importableExercises.filter { $0.trimmedName.contains(where: \.isLetter) }
        let hasMetric = exercises.contains { exercise in
            exercise.sets.contains { $0.reps != nil || $0.weight != nil || $0.distance != nil || $0.durationSeconds != nil }
        }
        guard hasMetric else { return false }
        if containsTrainingNotation(trimmed) { return true }
        let setCount = exercises.reduce(0) { $0 + $1.sets.count }
        guard exercises.count >= 2 || setCount >= 2 else { return false }
        let lines = trimmed.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let numericLines = lines.filter { $0.contains(where: \.isNumber) }
        let priceLines = numericLines.filter { $0.firstMatch(of: /[$€£¥]\s*\d|\d+[.,]\d{2}\b/) != nil }
        return numericLines.count * 2 >= lines.count
            && parsed.droppedLines.count * 2 <= lines.count
            && priceLines.count * 2 < numericLines.count
    }

    static func containsTrainingNotation(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.firstMatch(of: /\d+\s*[x×]\s*\d+/) != nil { return true }
        return lower.firstMatch(of: /\b(reps?|sets? of|amrap|emom|rpe|rounds?|wod|tabata|superset|for time)\b/) != nil
    }
}

// The VisualIntelligence framework ships in the device SDK only; the simulator SDK
// used by the unit tests has no module, so only the system entry point is gated.
// Everything it decides with lives above and is unit-tested.
#if canImport(VisualIntelligence)
/// Visual Intelligence entry point. Returns at most one result, and none at all
/// unless the recognized text plausibly contains a workout.
nonisolated struct WorkoutVisualSearchQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [WorkoutCaptureEntity] {
        guard let buffer = input.pixelBuffer, let image = Self.cgImage(from: buffer) else { return [] }
        guard let text = try? await VisionWorkoutTextRecognizer().recognizeText(in: image) else { return [] }
        return WorkoutVisualSearch.result(forRecognizedText: text).map { [$0] } ?? []
    }

    /// Converts Visual Intelligence's frame for Marble's CGImage recognizer.
    static func cgImage(from buffer: CVReadOnlyPixelBuffer) -> CGImage? {
        buffer.withUnsafeBuffer { pixelBuffer -> CGImage? in
            var image: CGImage?
            if VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image) == noErr, let image {
                return image
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
    }
}
#endif
