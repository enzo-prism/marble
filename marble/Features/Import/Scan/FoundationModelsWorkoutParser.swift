import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structures OCR text with Apple's on-device language model (Apple Intelligence),
/// falling back to the deterministic parser when the model is unavailable — older
/// hardware, Apple Intelligence turned off, the model still downloading, or any
/// generation error. Everything runs on device, so the local-only privacy posture is
/// preserved; nothing is sent off the phone.
nonisolated struct FoundationModelsWorkoutScanParser: WorkoutScanParsing {
    private let fallback: WorkoutScanParsing

    init(fallback: WorkoutScanParsing = HeuristicWorkoutScanParser()) {
        self.fallback = fallback
    }

    /// True only when the on-device model is ready to use right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            if let draft = await generate(ocrText: ocrText, referenceDate: referenceDate) {
                return draft
            }
        }
        #endif
        return await fallback.parse(ocrText: ocrText, referenceDate: referenceDate)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generate(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft? {
        let instructions = """
            You convert the raw text of a photographed handwritten workout log into \
            structured data. Only use information present in the text. Do not invent \
            exercises, sets, weights, or reps. If a value is not written, leave it 0 \
            (or empty for units). Expand common gym shorthand: "3x5" means 3 sets of 5 \
            reps; "@135" or "135 lb" is the weight; "5k" is a 5 kilometer distance; \
            "25:00" is a duration of 25 minutes.
            """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Parse this workout into structured data:\n\n\(ocrText)"

        do {
            let response = try await session.respond(to: prompt, generating: GeneratedWorkout.self)
            let draft = response.content.draft(referenceDate: referenceDate)
            // The model occasionally returns nothing usable; let the deterministic
            // parser try rather than importing an empty workout.
            return draft.hasContent ? draft : nil
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedWorkout {
    @Guide(description: "An optional title or focus written on the page, e.g. \"Push Day\". Empty if none.")
    var title: String
    @Guide(description: "Every distinct exercise written on the page.")
    var exercises: [GeneratedExercise]

    func draft(referenceDate: Date) -> ParsedWorkoutDraft {
        let mapped = exercises.compactMap { $0.draft() }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedWorkoutDraft(
            performedAt: nil,
            title: cleanTitle.isEmpty ? "Scanned workout" : cleanTitle,
            exercises: mapped
        )
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedExercise {
    @Guide(description: "The exercise name, e.g. \"Bench Press\" or \"Run\".")
    var name: String
    @Guide(description: "Each set performed for this exercise.")
    var sets: [GeneratedSet]

    func draft() -> ParsedExerciseDraft? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let mappedSets = sets.compactMap { $0.draft() }
        guard !mappedSets.isEmpty else { return nil }
        return ParsedExerciseDraft(name: cleanName, sets: mappedSets)
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedSet {
    @Guide(description: "Repetitions for this set. 0 if not written or not applicable.")
    var reps: Int
    @Guide(description: "Weight value for this set. 0 if bodyweight or not written.")
    var weight: Double
    @Guide(description: "Weight unit: \"lb\" or \"kg\". Default to \"lb\" if unclear.")
    var weightUnit: String
    @Guide(description: "Distance value for a cardio set. 0 if not a distance exercise.")
    var distance: Double
    @Guide(description: "Distance unit: \"m\", \"km\", \"mi\", \"yd\", or \"ft\". Empty if none.")
    var distanceUnit: String
    @Guide(description: "Duration in seconds for a timed or cardio set. 0 if not written.")
    var durationSeconds: Int

    func draft() -> ParsedSetDraft? {
        let resolvedReps = reps > 0 ? reps : nil
        let resolvedWeight = weight > 0 ? weight : nil
        let resolvedDistance = distance > 0 ? distance : nil
        let resolvedDuration = durationSeconds > 0 ? durationSeconds : nil
        guard resolvedReps != nil || resolvedWeight != nil || resolvedDistance != nil || resolvedDuration != nil else {
            return nil
        }
        return ParsedSetDraft(
            weight: resolvedWeight,
            weightUnit: weightUnit.lowercased().hasPrefix("kg") ? .kg : .lb,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: Self.distanceUnit(from: distanceUnit),
            durationSeconds: resolvedDuration
        )
    }

    private static func distanceUnit(from raw: String) -> DistanceUnit {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "km", "k", "kilometer", "kilometers": return .kilometers
        case "mi", "mile", "miles": return .miles
        case "yd", "yard", "yards": return .yards
        case "ft", "feet", "foot": return .feet
        default: return .meters
        }
    }
}
#endif
