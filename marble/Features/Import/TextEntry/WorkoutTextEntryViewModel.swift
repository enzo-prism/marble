import Foundation
import SwiftData
import SwiftUI

/// Drives the "type or paste a workout" flow: free text → on-device parse →
/// structured draft with per-exercise library matching → user review/approve →
/// journal. The parser and import handler are injected so the orchestration is
/// unit-testable without the on-device model or a real store.
///
/// The parsing pipeline is the scan flow's minus OCR: the same
/// `WorkoutScanParsing` conformers (Apple's on-device model when available, the
/// deterministic notation parser otherwise) consume the typed text directly, so
/// nothing ever leaves the device.
@Observable
@MainActor
final class WorkoutTextEntryViewModel {
    enum Phase: Equatable {
        case input
        case processing
        case review
        case imported
    }

    /// How one parsed exercise maps onto the library, shown and adjustable in
    /// the review step — the piece the silent importers don't have.
    struct Resolution: Equatable {
        enum Choice: Equatable {
            /// Import into this existing library exercise (canonical name).
            case library(id: UUID, name: String)
            /// Create a new exercise named after the parsed text.
            case createNew
        }

        var choice: Choice
        /// Ranked plausible library matches for the picker, best first.
        var suggestions: [ExerciseMatcher.Match]
        /// Confidence of the automatic pick; nil once the user overrides it.
        var autoConfidence: ExerciseMatcher.Confidence?
    }

    typealias ImportHandler = (ParsedWorkoutDraft, String, ModelContext) throws -> WorkoutImporter.Summary

    private(set) var phase: Phase = .input
    var text = ""
    var draft = ParsedWorkoutDraft()
    private(set) var resolutions: [UUID: Resolution] = [:]
    private(set) var lastSummary: WorkoutImporter.Summary?
    var errorMessage: String?
    /// Set when identical text was already imported — a heads-up, not a block.
    private(set) var alreadyImported = false
    private(set) var externalID = ""

    private let parser: WorkoutScanParsing
    /// Test seam: when nil, `commit` calls `WorkoutScanImporter` directly.
    private let importHandler: ImportHandler?
    private var matcher = ExerciseMatcher(candidates: [])

    init(
        parser: WorkoutScanParsing = FoundationModelsWorkoutScanParser(),
        importHandler: ImportHandler? = nil
    ) {
        self.parser = parser
        self.importHandler = importHandler
    }

    /// True only when the smarter on-device model is ready; the deterministic
    /// parser is always used as a fallback regardless.
    var usesOnDeviceModel: Bool { FoundationModelsWorkoutScanParser.isAvailable }

    static let defaultTitle = "Typed workout"

    // MARK: - Parse

    func preview(in context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Type or paste a workout first."
            return
        }
        phase = .processing
        errorMessage = nil
        // The text itself is the import identity: pasting the same log twice
        // dedupes exactly like re-scanning the same photo.
        externalID = WorkoutScanImageHash.hash(Data(trimmed.utf8))

        var parsed = await parser.parse(ocrText: trimmed, referenceDate: AppEnvironment.now)
        if parsed.title == ParsedWorkoutDraft().title { parsed.title = Self.defaultTitle }
        draft = parsed

        guard draft.hasContent else {
            errorMessage = "Couldn't find any exercises in that text. Try one exercise per line, like \"Bench Press 3x8 @ 185, rest 90s\"."
            phase = .input
            return
        }

        reloadMatcher(in: context)
        resolutions = [:]
        for exercise in draft.exercises {
            resolutions[exercise.id] = makeResolution(for: exercise.name)
        }
        alreadyImported = (try? WorkoutScanImporter.alreadyImported(
            externalID: externalID,
            source: .textEntry,
            in: context
        )) ?? false
        phase = .review
    }

    private func reloadMatcher(in context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        matcher = ExerciseMatcher(candidates: exercises.map {
            ExerciseMatcher.Candidate(id: $0.id, name: $0.name)
        })
    }

    private func makeResolution(for name: String) -> Resolution {
        let suggestions = matcher.topMatches(for: name)
        guard let best = suggestions.first else {
            return Resolution(choice: .createNew, suggestions: [], autoConfidence: nil)
        }
        return Resolution(
            choice: .library(id: best.candidate.id, name: best.candidate.name),
            suggestions: suggestions,
            autoConfidence: best.confidence
        )
    }

    // MARK: - Review editing

    func resolution(for exerciseID: UUID) -> Resolution? {
        resolutions[exerciseID]
    }

    func choose(_ choice: Resolution.Choice, for exerciseID: UUID) {
        guard var resolution = resolutions[exerciseID] else { return }
        resolution.choice = choice
        resolution.autoConfidence = nil
        resolutions[exerciseID] = resolution
    }

    /// Re-match after the user edits a parsed name; any manual pick is reset
    /// because it referred to the old name.
    func refreshResolution(forExerciseWithID id: UUID) {
        guard let exercise = draft.exercises.first(where: { $0.id == id }) else { return }
        resolutions[id] = makeResolution(for: exercise.name)
    }

    /// Exercises that will create a new library row as things stand.
    var newExerciseCount: Int {
        draft.importableExercises.filter { resolutions[$0.id]?.choice == .createNew }.count
    }

    func addExercise() {
        let exercise = ParsedExerciseDraft(name: "", sets: [ParsedSetDraft(reps: 1)])
        draft.exercises.append(exercise)
        resolutions[exercise.id] = Resolution(choice: .createNew, suggestions: [], autoConfidence: nil)
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
            performedAt: template.performedAt
        ))
    }

    func removeExercise(withID id: UUID) {
        draft.exercises.removeAll { $0.id == id }
        resolutions[id] = nil
    }

    func removeSets(fromExerciseWithID id: UUID, at offsets: IndexSet) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        draft.exercises[index].sets.remove(atOffsets: offsets)
        if draft.exercises[index].sets.isEmpty {
            removeExercise(withID: id)
        }
    }

    // MARK: - Commit

    func commit(into context: ModelContext) {
        guard draft.hasContent else {
            errorMessage = "Add at least one exercise with a set before importing."
            return
        }
        errorMessage = nil

        // Library picks import under the canonical library name, so the
        // importer's exact-name resolution lands on the existing row instead of
        // creating a near-duplicate.
        var toImport = draft
        for index in toImport.exercises.indices {
            let id = toImport.exercises[index].id
            if case let .library(_, name)? = resolutions[id]?.choice {
                toImport.exercises[index].name = name
            }
        }

        do {
            let summary = try importHandler?(toImport, externalID, context)
                ?? WorkoutScanImporter.import(toImport, externalID: externalID, source: .textEntry, in: context)
            lastSummary = summary
            if summary.importedSets > 0 {
                MarbleHaptics.success()
            } else {
                MarbleHaptics.lightImpact()
            }
            // Same contract as the scan flow: new library rows owe Spotlight
            // and the parameterised Siri phrases a refresh, detached so the
            // user isn't waiting on indexing.
            if summary.createdExercises > 0 {
                Task { await ExerciseSpotlightIndex.refreshAfterLibraryChange() }
            }
            phase = .imported
        } catch {
            errorMessage = "Couldn't save the workout. Please try again."
            MarbleHaptics.error()
        }
    }

    /// Back to the input step keeping the text, so a bad parse is editable.
    func editText() {
        phase = .input
        errorMessage = nil
    }

    func reset() {
        phase = .input
        text = ""
        draft = ParsedWorkoutDraft()
        resolutions = [:]
        lastSummary = nil
        errorMessage = nil
        alreadyImported = false
        externalID = ""
    }
}
