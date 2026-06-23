import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Drives the scan flow: image → on-device text recognition → structured draft →
/// user review/edit → journal. Recognizer, parser, and import handler are injected so
/// the orchestration is unit-testable without the camera, Vision, or the model.
@Observable
@MainActor
final class WorkoutScanViewModel {
    enum Phase: Equatable {
        case capture
        case processing
        case review
        case imported
    }

    typealias ImportHandler = (ParsedWorkoutDraft, String, ModelContext) throws -> WorkoutImporter.Summary

    private(set) var phase: Phase = .capture
    var draft = ParsedWorkoutDraft()
    private(set) var lastSummary: WorkoutImporter.Summary?
    var errorMessage: String?
    /// Set when the same photo was already imported — surfaced as a heads-up, not a block.
    private(set) var alreadyImported = false

    private(set) var externalID = ""

    private let recognizer: WorkoutTextRecognizing
    private let parser: WorkoutScanParsing
    /// Test seam: when nil, `commit` calls `WorkoutScanImporter` directly (on the main
    /// actor, where it belongs).
    private let importHandler: ImportHandler?

    init(
        recognizer: WorkoutTextRecognizing = VisionWorkoutTextRecognizer(),
        parser: WorkoutScanParsing = FoundationModelsWorkoutScanParser(),
        importHandler: ImportHandler? = nil
    ) {
        self.recognizer = recognizer
        self.parser = parser
        self.importHandler = importHandler
    }

    /// True only when the smarter on-device model is ready; the deterministic parser is
    /// always used as a fallback regardless.
    var usesOnDeviceModel: Bool { FoundationModelsWorkoutScanParser.isAvailable }

    // MARK: - Capture entry points

    func process(image: UIImage, in context: ModelContext) async {
        guard let cgImage = image.cgImage else {
            fail(with: "That image couldn't be read. Try scanning the page again.")
            return
        }
        let data = image.jpegData(compressionQuality: 0.85) ?? Data()
        await process(cgImage: cgImage, imageData: data, in: context)
    }

    /// Core orchestration (no UIKit) so tests can drive it directly.
    func process(cgImage: CGImage, imageData: Data, in context: ModelContext) async {
        phase = .processing
        errorMessage = nil
        externalID = WorkoutScanImageHash.hash(imageData.isEmpty ? Data(UUID().uuidString.utf8) : imageData)

        let text: String
        do {
            text = try await recognizer.recognizeText(in: cgImage)
        } catch {
            fail(with: "Couldn't read text from that image. Try better lighting or a flatter page.")
            return
        }

        let parsed = await parser.parse(ocrText: text, referenceDate: AppEnvironment.now)
        draft = parsed
        alreadyImported = (try? WorkoutScanImporter.alreadyImported(externalID: externalID, in: context)) ?? false
        phase = .review
    }

    private func fail(with message: String) {
        errorMessage = message
        phase = .capture
        MarbleHaptics.warning()
    }

    // MARK: - Review editing

    func addExercise() {
        draft.exercises.append(ParsedExerciseDraft(name: "", sets: [ParsedSetDraft(reps: 1)]))
    }

    func addSet(toExerciseWithID id: UUID) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let template = draft.exercises[index].sets.last ?? ParsedSetDraft(reps: 1)
        draft.exercises[index].sets.append(ParsedSetDraft(
            weight: template.weight,
            weightUnit: template.weightUnit,
            reps: template.reps,
            distance: template.distance,
            distanceUnit: template.distanceUnit,
            durationSeconds: template.durationSeconds
        ))
    }

    func removeExercises(at offsets: IndexSet) {
        draft.exercises.remove(atOffsets: offsets)
    }

    func removeExercise(withID id: UUID) {
        draft.exercises.removeAll { $0.id == id }
    }

    func removeSets(fromExerciseWithID id: UUID, at offsets: IndexSet) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        draft.exercises[index].sets.remove(atOffsets: offsets)
        if draft.exercises[index].sets.isEmpty {
            draft.exercises.remove(at: index)
        }
    }

    // MARK: - Commit

    func commit(into context: ModelContext) {
        guard draft.hasContent else {
            errorMessage = "Add at least one exercise with a set before importing."
            return
        }
        errorMessage = nil
        do {
            let summary = try importHandler?(draft, externalID, context)
                ?? WorkoutScanImporter.import(draft, externalID: externalID, in: context)
            lastSummary = summary
            if summary.importedSets > 0 {
                MarbleHaptics.success()
            } else {
                MarbleHaptics.lightImpact()
            }
            phase = .imported
        } catch {
            errorMessage = "Couldn't save the scanned workout. Please try again."
            MarbleHaptics.warning()
        }
    }

    func reset() {
        phase = .capture
        draft = ParsedWorkoutDraft()
        lastSummary = nil
        errorMessage = nil
        alreadyImported = false
        externalID = ""
    }
}
