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
    /// Source lines the parse produced nothing for, shown in review so a paste
    /// never loses work silently. Editable inline; a fixed line re-parses into
    /// the draft.
    private(set) var unparsedLines: [String] = []
    /// Debounced parse of the in-progress text for the input step's live
    /// per-line feedback. Deterministic parser only — it is pure and cheap, and
    /// the feedback must work on devices without the on-device model.
    private(set) var livePreview: LivePreview?
    /// Current pipeline stage while `phase == .processing` — drives the
    /// determinate progress bar. Reset to the first stage on every preview.
    private(set) var parseStage: WorkoutParseStage = .readingNotation
    /// Post-import celebration details for the imported screen.
    private(set) var celebration = ImportCelebration(volumeText: nil, prExercises: [])

    /// Extras for the imported screen beyond the raw counts: how much work the
    /// workout added up to, and which existing records it beat.
    struct ImportCelebration: Equatable {
        /// Total tonnage (Σ weight × reps) in the user's preferred unit,
        /// e.g. "14,805 lb". nil when the workout carried no weighted reps.
        var volumeText: String?
        /// Names of existing library exercises whose records the imported sets
        /// beat, in draft order. New exercises have no record to beat.
        var prExercises: [String]
    }

    struct LivePreview: Equatable {
        struct Recognized: Equatable, Identifiable {
            var id: UUID
            var name: String
            var setCount: Int
        }
        var recognized: [Recognized]
        var unrecognized: [String]
    }

    private let parser: WorkoutScanParsing
    /// Test seam: when nil, `commit` calls `WorkoutScanImporter` directly.
    private let importHandler: ImportHandler?
    /// Unit assumed for weights written without one ("Bench 3x8 @ 100") — the
    /// user's preferred unit, not a hardcoded lb.
    private let defaultWeightUnit: WeightUnit
    private var matcher = ExerciseMatcher(candidates: [])

    /// The weight unit the user picked in onboarding / settings.
    static var preferredWeightUnit: WeightUnit {
        WeightUnit(rawValue: SharedDefaults.suite.string(forKey: SharedDefaults.Key.preferredWeightUnit) ?? "") ?? .lb
    }

    init(
        parser: WorkoutScanParsing? = nil,
        importHandler: ImportHandler? = nil,
        defaultWeightUnit: WeightUnit = WorkoutTextEntryViewModel.preferredWeightUnit
    ) {
        self.defaultWeightUnit = defaultWeightUnit
        self.parser = parser ?? FoundationModelsWorkoutScanParser(defaultWeightUnit: defaultWeightUnit)
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
        parseStage = .readingNotation
        errorMessage = nil
        // The text itself is the import identity: pasting the same log twice
        // dedupes exactly like re-scanning the same photo.
        externalID = WorkoutScanImageHash.hash(Data(trimmed.utf8))

        var parsed = await parser.parse(ocrText: trimmed, referenceDate: AppEnvironment.now) { stage in
            await MainActor.run { self.parseStage = stage }
        }
        if parsed.title == ParsedWorkoutDraft().title { parsed.title = Self.defaultTitle }
        draft = parsed

        guard draft.hasContent else {
            errorMessage = "Couldn't find any exercises in that text. Try one exercise per line, like \"Bench Press 3x8 @ 185, rest 90s\"."
            phase = .input
            return
        }

        // Lines nothing claimed, from the deterministic pass over the original
        // text. A line the winning draft obviously used (it names a parsed
        // exercise) is not "unparsed" — this keeps the section honest when the
        // on-device model read prose the notation parser could not.
        let diagnostics = HandwrittenWorkoutParser.parseDetailed(
            trimmed,
            referenceDate: AppEnvironment.now,
            defaultWeightUnit: defaultWeightUnit
        )
        unparsedLines = diagnostics.droppedLines.filter { line in
            let lowered = line.lowercased()
            return !draft.importableExercises.contains { exercise in
                let name = exercise.trimmedName.lowercased()
                return !name.isEmpty && (lowered.contains(name) || name.contains(lowered))
            }
        }

        parseStage = .finalizing
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

    // MARK: - Unparsed lines

    /// Re-parse one "couldn't read" line after the user edits it. A line that
    /// now yields exercises joins the draft (with fresh library matching) and
    /// leaves the list; one that still doesn't parse stays, updated in place.
    func retryUnparsedLine(at index: Int, replacement: String) async {
        guard unparsedLines.indices.contains(index) else { return }
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            unparsedLines.remove(at: index)
            return
        }
        let parsed = await parser.parse(ocrText: trimmed, referenceDate: AppEnvironment.now)
        let newExercises = parsed.importableExercises
        guard !newExercises.isEmpty else {
            unparsedLines[index] = trimmed
            return
        }
        for exercise in newExercises {
            draft.exercises.append(exercise)
            resolutions[exercise.id] = makeResolution(for: exercise.name)
        }
        unparsedLines.remove(at: index)
    }

    // MARK: - Live preview

    /// Recomputes the input step's per-line feedback. Synchronous and cheap:
    /// the deterministic parser is pure string work, so per-keystroke is fine.
    func updateLivePreview() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            livePreview = nil
            return
        }
        let result = HandwrittenWorkoutParser.parseDetailed(
            trimmed,
            referenceDate: AppEnvironment.now,
            defaultWeightUnit: defaultWeightUnit
        )
        livePreview = LivePreview(
            recognized: result.draft.importableExercises.map {
                LivePreview.Recognized(id: $0.id, name: $0.trimmedName, setCount: $0.sets.count)
            },
            unrecognized: result.droppedLines
        )
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

    /// Move one exercise earlier/later in the review list. Draft order is
    /// import order — the importer's ordinal cascade preserves it in the
    /// journal — so this is also how a user fixes the saved workout's order.
    /// (Button-based rather than `.onMove`: the review list renders one
    /// `Section` per exercise, and SwiftUI move handles only work within a
    /// single section.)
    func moveExercise(withID id: UUID, by delta: Int) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard draft.exercises.indices.contains(target) else { return }
        draft.exercises.swapAt(index, target)
    }

    /// Position of an exercise in the review list, for enabling/disabling the
    /// move controls.
    func exerciseIndex(withID id: UUID) -> Int? {
        draft.exercises.firstIndex { $0.id == id }
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

        // Compute the celebration BEFORE the import lands: records to beat are
        // the ones on file prior to this workout.
        celebration = computeCelebration(for: toImport, in: context)

        do {
            let summary = try importHandler?(toImport, externalID, context)
                ?? WorkoutScanImporter.import(toImport, externalID: externalID, source: .textEntry, in: context)
            lastSummary = summary
            if summary.importedSets > 0 {
                MarbleHaptics.success()
                if celebration.prExercises.isEmpty {
                    ReviewPrompt.consider(after: .importedWorkout)
                } else {
                    ReviewPrompt.consider(after: .personalRecord)
                }
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

    /// Volume + PR detection for the imported screen. Pure lookups against the
    /// same tested record engine the journal uses; runs pre-import so "records
    /// to beat" means records on file before this workout.
    private func computeCelebration(for draft: ParsedWorkoutDraft, in context: ModelContext) -> ImportCelebration {
        var volumeKilograms = 0.0
        var prExercises: [String] = []

        for exercise in draft.importableExercises {
            for set in exercise.sets {
                if let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 {
                    volumeKilograms += PersonalRecords.kilograms(weight, unit: set.weightUnit) * Double(reps)
                }
            }

            // Only an existing library exercise has records to beat; a freshly
            // created one is celebrated as "new in your library" instead.
            let name = exercise.trimmedName
            var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            guard let existing = (try? context.fetch(descriptor))?.first else { continue }
            // A plain local UUID: the predicate macro can't capture member
            // access (`existing.id`) into a fetched object.
            let existingID = existing.id
            let entries = (try? context.fetch(FetchDescriptor<SetEntry>(
                predicate: #Predicate { $0.exercise.id == existingID }
            ))) ?? []
            let records = PersonalRecords.records(for: existing, entries: entries)
            guard records.hasAnyBest else { continue }
            let beatsRecord = exercise.sets.contains { set in
                !PersonalRecords.projectedBadge(
                    storedWeight: set.weight,
                    weightUnit: set.weightUnit,
                    reps: set.reps,
                    beating: records,
                    metrics: existing.metrics
                ).isEmpty
            }
            if beatsRecord { prExercises.append(existing.name) }
        }

        var volumeText: String?
        if volumeKilograms > 0 {
            let poundsPerKilogram = 1 / 0.45359237
            let inPreferred = defaultWeightUnit == .kg ? volumeKilograms : volumeKilograms * poundsPerKilogram
            let rounded = Self.volumeFormatter.string(from: NSNumber(value: inPreferred)) ?? "\(Int(inPreferred.rounded()))"
            volumeText = "\(rounded) \(defaultWeightUnit.symbol)"
        }
        return ImportCelebration(volumeText: volumeText, prExercises: prExercises)
    }

    /// Integer with thousands separators ("14,805") — tonnage reads as a big
    /// round achievement number, decimals would only add noise.
    private static let volumeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    func reset() {
        phase = .input
        text = ""
        draft = ParsedWorkoutDraft()
        resolutions = [:]
        lastSummary = nil
        errorMessage = nil
        alreadyImported = false
        externalID = ""
        unparsedLines = []
        livePreview = nil
        parseStage = .readingNotation
        celebration = ImportCelebration(volumeText: nil, prExercises: [])
    }
}
