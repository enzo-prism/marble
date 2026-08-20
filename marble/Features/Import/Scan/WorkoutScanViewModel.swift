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
        /// OCR found more than one dated workout. The scan sheet hands the
        /// concatenated text to the typed pipeline so library matching and
        /// batch review apply — scan review is one draft.
        case textHandoff
    }

    typealias ImportHandler = (ParsedWorkoutDraft, String, ModelContext) throws -> WorkoutImporter.Summary

    private(set) var phase: Phase = .capture
    var draft = ParsedWorkoutDraft()
    private(set) var lastSummary: WorkoutImporter.Summary?
    var errorMessage: String?
    /// Set when the same photo was already imported — surfaced as a heads-up, not a block.
    private(set) var alreadyImported = false

    private(set) var externalID = ""
    /// Concatenated OCR when `phase == .textHandoff`.
    private(set) var handoffText = ""

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
        await process(images: [image], in: context)
    }

    func process(images: [UIImage], in context: ModelContext) async {
        var pages: [(cgImage: CGImage, imageData: Data)] = []
        pages.reserveCapacity(images.count)
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            pages.append((cgImage, image.jpegData(compressionQuality: 0.85) ?? Data()))
        }
        guard !pages.isEmpty else {
            fail(with: "That image couldn't be read. Try scanning the page again.")
            return
        }
        await process(pages: pages, in: context)
    }

    /// Core orchestration (no UIKit) so tests can drive it directly.
    func process(cgImage: CGImage, imageData: Data, in context: ModelContext) async {
        await process(pages: [(cgImage, imageData)], in: context)
    }

    func process(
        pages: [(cgImage: CGImage, imageData: Data)],
        in context: ModelContext
    ) async {
        phase = .processing
        errorMessage = nil
        handoffText = ""
        let combinedData = pages.reduce(into: Data()) { $0.append($1.imageData) }
        externalID = WorkoutScanImageHash.hash(combinedData.isEmpty ? Data(UUID().uuidString.utf8) : combinedData)

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pages.count)
        for page in pages {
            let text: String
            do {
                text = try await recognizer.recognizeText(in: page.cgImage)
            } catch {
                fail(with: "Couldn't read text from that image. Try better lighting or a flatter page.")
                return
            }
            pageTexts.append(text)
        }

        let combined = Self.joinOCR(pageTexts)
        guard !combined.isEmpty else {
            fail(with: "Couldn't read text from that image. Try better lighting or a flatter page.")
            return
        }

        let segments = WorkoutSessionSegmenter.segments(from: combined, referenceDate: AppEnvironment.now)
        if segments.count > 1 {
            handoffText = combined
            phase = .textHandoff
            return
        }

        let parsed = await parser.parse(ocrText: combined, referenceDate: AppEnvironment.now)
        draft = parsed
        alreadyImported = (try? WorkoutScanImporter.alreadyImported(externalID: externalID, in: context)) ?? false
        phase = .review
    }

    /// Joins OCR from successive notebook pages. Blank pages drop out so they
    /// don't become fake session breaks.
    static func joinOCR(_ pageTexts: [String]) -> String {
        pageTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func fail(with message: String) {
        errorMessage = message
        phase = .capture
        MarbleHaptics.error()
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
            durationSeconds: template.durationSeconds,
            restSeconds: template.restSeconds,
            performedAt: template.performedAt,
            difficulty: template.difficulty
        ))
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
                ReviewPrompt.consider(after: .importedWorkout)
            } else {
                MarbleHaptics.lightImpact()
            }
            // A scanned workout can invent library rows too; refresh Spotlight
            // and the parameterised Siri phrases straight away. Detached from
            // the commit because `commit` is synchronous and the user should not
            // wait on indexing to see the imported state.
            if summary.createdExercises > 0 {
                Task { await ExerciseSpotlightIndex.refreshAfterLibraryChange() }
            }
            phase = .imported
        } catch {
            errorMessage = "Couldn't save the scanned workout. Please try again."
            MarbleHaptics.error()
        }
    }

    func reset() {
        phase = .capture
        draft = ParsedWorkoutDraft()
        lastSummary = nil
        errorMessage = nil
        alreadyImported = false
        externalID = ""
        handoffText = ""
    }
}
