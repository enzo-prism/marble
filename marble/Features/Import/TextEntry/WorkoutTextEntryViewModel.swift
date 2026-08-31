import Foundation
import SwiftData
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

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
        case batchReview
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

        /// Exact and strong matches bind to the library. Likely matches stay
        /// suggestions but default to creating a new row so "Bench" does not
        /// silently merge into "Bench Press".
        static func automatic(for name: String, matcher: ExerciseMatcher) -> Resolution {
            let suggestions = matcher.topMatches(for: name)
            guard let best = suggestions.first else {
                return Resolution(choice: .createNew, suggestions: [], autoConfidence: nil)
            }
            let choice: Choice
            if best.confidence >= .strong {
                choice = .library(id: best.candidate.id, name: best.candidate.name)
            } else {
                choice = .createNew
            }
            return Resolution(
                choice: choice,
                suggestions: suggestions,
                autoConfidence: best.confidence
            )
        }
    }

    typealias ImportHandler = (ParsedWorkoutDraft, String, ModelContext) throws -> WorkoutImporter.Summary

    private(set) var phase: Phase = .input
    var text = ""
    var draft = ParsedWorkoutDraft()
    private(set) var sessions: [WorkoutImportSession] = []
    /// Set when the review screen is a drill-in from `batchReview`.
    private(set) var reviewingSessionID: UUID?
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
    /// Stable identity for each displayed row. The same dropped line can occur
    /// more than once, so its text is not a safe concurrency key while retries
    /// yield to the parser.
    private var unparsedLineIDs: [UUID] = []
    private var retryingUnparsedLineIDs: Set<UUID> = []
    /// Debounced parse of the in-progress text for the input step's live
    /// per-line feedback. Deterministic parser only, so feedback works on every
    /// device; the pure parse runs off the main actor for responsive typing.
    private(set) var livePreview: LivePreview?
    /// Current pipeline stage while `phase == .processing` — drives the status
    /// copy beside an indeterminate spinner. Reset on every preview.
    private(set) var parseStage: WorkoutParseStage = .readingNotation
    /// 1-based index of the session currently being parsed, when a paste
    /// split into more than one workout.
    private(set) var batchProgress: (current: Int, total: Int)?
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

    nonisolated struct LivePreview: Equatable, Sendable {
        nonisolated struct Recognized: Equatable, Identifiable, Sendable {
            /// Stable source-position identity keeps SwiftUI from replacing
            /// every preview row after each debounced parse.
            var id: String
            var name: String
            var setCount: Int
        }
        var recognized: [Recognized]
        var unrecognized: [String]
        var sessionCount: Int = 1
        var totalSets: Int = 0
    }

    private let parser: WorkoutScanParsing
    /// Test seam: when nil, `commit` calls `WorkoutScanImporter` directly.
    private let importHandler: ImportHandler?
    /// Unit assumed for weights written without one ("Bench 3x8 @ 100") — the
    /// user's preferred unit, not a hardcoded lb.
    private let defaultWeightUnit: WeightUnit
    private var matcher = ExerciseMatcher(candidates: [])
    /// Bumped on every `preview` so a second tap cancels the in-flight parse.
    private var previewGeneration = 0

    /// The weight unit the user picked in onboarding / settings.
    static var preferredWeightUnit: WeightUnit {
        WeightUnit(rawValue: SharedDefaults.suite.string(forKey: SharedDefaults.Key.preferredWeightUnit) ?? "") ?? .lb
    }

    init(
        parser: WorkoutScanParsing? = nil,
        importHandler: ImportHandler? = nil,
        defaultWeightUnit: WeightUnit = WorkoutTextEntryViewModel.preferredWeightUnit,
        initialText: String = ""
    ) {
        self.defaultWeightUnit = defaultWeightUnit
        self.parser = parser ?? FoundationModelsWorkoutScanParser(defaultWeightUnit: defaultWeightUnit)
        self.importHandler = importHandler
        self.text = initialText
    }

    /// True only when the smarter on-device model is ready; the deterministic
    /// parser is always used as a fallback regardless.
    var usesOnDeviceModel: Bool { FoundationModelsWorkoutScanParser.isAvailable }

    /// Privacy / availability line under the editor. Matches Apple's
    /// `SystemLanguageModel.availability` cases instead of a generic lock label.
    var privacyCaption: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Read on your device with Apple Intelligence — nothing is uploaded."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence to read prose; gym notation still works on device. Nothing is uploaded."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Gym notation still works on this device."
            case .unavailable(.deviceNotEligible):
                return "Read on your device — nothing is uploaded."
            default:
                return "Read on your device — nothing is uploaded."
            }
        }
        #endif
        return "Read on your device — nothing is uploaded."
    }

    func ingestPastedText(_ pasted: String) {
        let incoming = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = existing.isEmpty ? incoming : WorkoutImportOrchestrator.joinSources([existing, incoming])
    }

    func ingestSources(_ parts: [String]) {
        let joined = WorkoutImportOrchestrator.joinSources(parts)
        guard !joined.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = joined
        } else {
            ingestPastedText(joined)
        }
    }

    static let defaultTitle = "Imported workout"

    // MARK: - Parse

    func preview(in context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Type or paste a workout first."
            return
        }
        previewGeneration += 1
        let generation = previewGeneration
        phase = .processing
        parseStage = .readingNotation
        batchProgress = nil
        errorMessage = nil
        reviewingSessionID = nil

        let segments = WorkoutImportOrchestrator.segments(
            from: trimmed,
            referenceDate: AppEnvironment.now,
            defaultWeightUnit: defaultWeightUnit
        )
        reloadMatcher(in: context)
        resolutions = [:]

        var built: [WorkoutImportSession] = []
        built.reserveCapacity(segments.count)
        for (index, segment) in segments.enumerated() {
            guard generation == previewGeneration else { return }
            batchProgress = (index + 1, segments.count)
            parseStage = .readingNotation
            let parsed = await parseSegment(segment, sessionCount: segments.count)
            let hasContent = parsed.draft.hasContent
            // Keep an unreadable block in a real multi-workout paste so the
            // review screen can point to it instead of silently dropping it.
            // A wholly unreadable single workout keeps the existing inline
            // guidance on the editor.
            guard hasContent || segments.count > 1 else { continue }

            let externalID = WorkoutImportOrchestrator.externalID(for: segment)
            let alreadyImported: Bool
            if hasContent {
                alreadyImported = (try? WorkoutScanImporter.alreadyImported(
                    externalID: externalID,
                    source: .textEntry,
                    in: context
                )) ?? false
                for exercise in parsed.draft.exercises {
                    resolutions[exercise.id] = makeResolution(for: exercise.name)
                }
            } else {
                alreadyImported = false
            }
            let unparsedLines = hasContent || !parsed.unparsedLines.isEmpty
                ? parsed.unparsedLines
                : reviewLines(in: segment.sourceText)
            built.append(WorkoutImportSession(
                sourceText: segment.sourceText,
                externalID: externalID,
                kind: segment.kind,
                draft: parsed.draft,
                unparsedLines: unparsedLines,
                alreadyImported: alreadyImported,
                selected: hasContent && !alreadyImported
            ))
        }

        guard generation == previewGeneration else { return }
        parseStage = .finalizing
        batchProgress = nil
        sessions = built

        guard sessions.contains(where: { $0.draft.hasContent }) else {
            errorMessage = "Couldn't find any exercises in that text. Try one exercise per line, like \"Bench Press 3x8 @ 185, rest 90s\", or import a Hevy/Strong CSV."
            phase = .input
            return
        }

        if sessions.count == 1 {
            presentSessionForReview(sessions[0].id)
            phase = .review
        } else {
            phase = .batchReview
        }
    }

    private func parseSegment(
        _ segment: WorkoutImportSegment,
        sessionCount: Int
    ) async -> (draft: ParsedWorkoutDraft, unparsedLines: [String]) {
        if var draft = segment.draft {
            if draft.title == ParsedWorkoutDraft().title { draft.title = Self.defaultTitle }
            return (draft, [])
        }

        let diagnostics = HandwrittenWorkoutParser.parseDetailed(
            segment.sourceText,
            referenceDate: AppEnvironment.now,
            defaultWeightUnit: defaultWeightUnit
        )
        // A bulk paste of clean gym notation is already solved by the
        // deterministic parser. Skip the on-device model per session so a week
        // of Notes doesn't pay 20 sequential Foundation Models passes.
        // Date headers are consumed by the parser, not dropped; filter anyway
        // so a leftover header never forces a model pass.
        let meaningfulDrops = diagnostics.droppedLines.filter { line in
            !HandwrittenWorkoutParser.isSessionSplitHeader(line, referenceDate: AppEnvironment.now)
        }
        if meaningfulDrops.isEmpty, diagnostics.draft.hasContent {
            var draft = diagnostics.draft
            if draft.title == ParsedWorkoutDraft().title { draft.title = Self.defaultTitle }
            return (draft, [])
        }

        var parsed = await parser.parse(ocrText: segment.sourceText, referenceDate: AppEnvironment.now) { stage in
            await MainActor.run { self.parseStage = stage }
        }
        if parsed.title == ParsedWorkoutDraft().title { parsed.title = Self.defaultTitle }
        let unparsed = diagnostics.droppedLines.filter { line in
            let lowered = line.lowercased()
            return !parsed.importableExercises.contains { exercise in
                let name = exercise.trimmedName.lowercased()
                return !name.isEmpty && (lowered.contains(name) || name.contains(lowered))
            }
        }
        return (parsed, unparsed)
    }

    private func presentSessionForReview(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        reviewingSessionID = id
        draft = session.draft
        unparsedLines = session.unparsedLines
        unparsedLineIDs = unparsedLines.map { _ in UUID() }
        alreadyImported = session.alreadyImported
        externalID = session.externalID
    }

    /// Persist review edits back onto the session they came from.
    private func persistOpenReview() {
        guard let id = reviewingSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let previouslyHadContent = sessions[index].draft.hasContent
        sessions[index].draft = draft
        sessions[index].unparsedLines = unparsedLines
        if !draft.hasContent {
            sessions[index].selected = false
        } else if !previouslyHadContent && !sessions[index].alreadyImported {
            sessions[index].selected = true
        }
    }

    /// User-relevant lines from a session the parser could not structure.
    /// Date/session headers stay represented by the row's date/title and do not
    /// inflate the "needs review" count.
    private func reviewLines(in sourceText: String) -> [String] {
        sourceText.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && !HandwrittenWorkoutParser.isSessionSplitHeader(
                        $0,
                        referenceDate: AppEnvironment.now
                    )
            }
    }

    private func reloadMatcher(in context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        matcher = ExerciseMatcher(candidates: exercises.map {
            ExerciseMatcher.Candidate(id: $0.id, name: $0.name)
        })
    }

    private func makeResolution(for name: String) -> Resolution {
        Resolution.automatic(for: name, matcher: matcher)
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
        guard unparsedLines.indices.contains(index),
              unparsedLineIDs.indices.contains(index) else { return }
        let lineID = unparsedLineIDs[index]
        guard retryingUnparsedLineIDs.insert(lineID).inserted else { return }
        defer { retryingUnparsedLineIDs.remove(lineID) }
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let currentIndex = unparsedLineIDs.firstIndex(of: lineID) {
                unparsedLines.remove(at: currentIndex)
                unparsedLineIDs.remove(at: currentIndex)
            }
            return
        }
        let parsed = await parser.parse(ocrText: trimmed, referenceDate: AppEnvironment.now)
        // Parsing yields the main actor. Another retry may have removed or
        // moved this row, so resolve it again by stable identity rather than
        // text, which may be identical in another row.
        guard let currentIndex = unparsedLineIDs.firstIndex(of: lineID) else { return }
        let newExercises = parsed.importableExercises
        guard !newExercises.isEmpty else {
            unparsedLines[currentIndex] = trimmed
            return
        }
        for exercise in newExercises {
            draft.exercises.append(exercise)
            resolutions[exercise.id] = makeResolution(for: exercise.name)
        }
        unparsedLines.remove(at: currentIndex)
        unparsedLineIDs.remove(at: currentIndex)
    }

    // MARK: - Live preview

    /// Immediate seam for explicit refreshes and deterministic unit/snapshot
    /// tests. Interactive typing uses the debounced async method below.
    func updateLivePreview() {
        livePreview = WorkoutLivePreviewBuilder.makePreview(
            text: text,
            referenceDate: AppEnvironment.now,
            defaultWeightUnit: defaultWeightUnit
        )
    }

    /// Waits for a short typing pause, builds off the main actor, then applies
    /// only if this text is still current. SwiftUI also cancels the enclosing
    /// `task(id:)`, while the equality checks protect non-view callers.
    func updateLivePreview(
        for sourceText: String,
        debounce: Duration = .milliseconds(180)
    ) async {
        do {
            try await Task.sleep(for: debounce)
        } catch {
            return
        }
        guard !Task.isCancelled, sourceText == text else { return }

        let referenceDate = AppEnvironment.now
        let preview = await WorkoutLivePreviewBuilder.build(
            text: sourceText,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit
        )
        guard !Task.isCancelled, sourceText == text else { return }
        livePreview = preview
    }

    /// Exercises that will create a new library row as things stand.
    /// Duplicate names across sessions count once — the importer reuses the
    /// first created row for later sessions of the same name.
    var newExerciseCount: Int {
        Set(
            exercisesPendingImport.compactMap { exercise -> String? in
                guard resolutions[exercise.id]?.choice == .createNew else { return nil }
                let name = exercise.trimmedName.lowercased()
                return name.isEmpty ? nil : name
            }
        ).count
    }

    /// How one batch row maps onto the library, for the honest subtitle.
    struct SessionMatchBreakdown: Equatable {
        var libraryCount: Int
        var newCount: Int
        var weakMatchCount: Int

        var line: String? {
            var parts: [String] = []
            if libraryCount > 0 {
                parts.append("\(libraryCount) library")
            }
            if newCount > 0 {
                parts.append("\(newCount) new")
            }
            if weakMatchCount > 0 {
                parts.append("\(weakMatchCount) weak match\(weakMatchCount == 1 ? "" : "es")")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    func matchBreakdown(for session: WorkoutImportSession) -> SessionMatchBreakdown {
        var libraryCount = 0
        var newCount = 0
        var weakMatchCount = 0
        for exercise in session.draft.importableExercises {
            guard let resolution = resolutions[exercise.id] else {
                newCount += 1
                continue
            }
            switch resolution.choice {
            case .createNew:
                newCount += 1
            case .library:
                libraryCount += 1
            }
            if resolution.autoConfidence == .likely {
                weakMatchCount += 1
            }
        }
        return SessionMatchBreakdown(
            libraryCount: libraryCount,
            newCount: newCount,
            weakMatchCount: weakMatchCount
        )
    }

    private var exercisesPendingImport: [ParsedExerciseDraft] {
        if phase == .batchReview {
            return importableSelectedSessions.flatMap(\.draft.importableExercises)
        }
        return draft.importableExercises
    }

    var isDrillingInFromBatch: Bool {
        phase == .review && sessions.count > 1
    }

    var selectedSessionCount: Int {
        importableSelectedSessions.count
    }

    var selectedSetCount: Int {
        importableSelectedSessions.reduce(0) { $0 + $1.draft.totalSetCount }
    }

    var importableSelectedSessions: [WorkoutImportSession] {
        sessions.filter { $0.selected && $0.draft.hasContent && !$0.alreadyImported }
    }

    /// Detected workout boundaries that still have no importable set. These
    /// stay visible in batch review and block saving so source text cannot be
    /// discarded without an explicit fix.
    var unresolvedSessionCount: Int {
        sessions.filter { !$0.draft.hasContent }.count
    }

    var canCommitSelectedSessions: Bool {
        unresolvedSessionCount == 0 && !importableSelectedSessions.isEmpty
    }

    var alreadyImportedSessionCount: Int {
        sessions.filter(\.alreadyImported).count
    }

    var allImportableSelected: Bool {
        let importable = sessions.filter { !$0.alreadyImported && $0.draft.hasContent }
        return !importable.isEmpty && importable.allSatisfy(\.selected)
    }

    var canToggleBatchSelection: Bool {
        sessions.contains { !$0.alreadyImported && $0.draft.hasContent }
    }

    func toggleSessionSelected(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard !sessions[index].alreadyImported, sessions[index].draft.hasContent else { return }
        sessions[index].selected.toggle()
    }

    func selectAllImportable() {
        for index in sessions.indices where !sessions[index].alreadyImported && sessions[index].draft.hasContent {
            sessions[index].selected = true
        }
    }

    func deselectAll() {
        for index in sessions.indices {
            sessions[index].selected = false
        }
    }

    func toggleSelectAllImportable() {
        if allImportableSelected {
            deselectAll()
        } else {
            selectAllImportable()
        }
    }

    func openSession(_ id: UUID) {
        persistOpenReview()
        presentSessionForReview(id)
        phase = .review
    }

    func returnToBatch() {
        persistOpenReview()
        reviewingSessionID = nil
        phase = .batchReview
        errorMessage = nil
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
            performedAt: template.performedAt,
            difficulty: template.difficulty,
            notes: template.notes
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
        persistOpenReview()
        if sessions.count > 1 {
            commitSelected(into: context)
            return
        }
        guard draft.hasContent else {
            errorMessage = "Add at least one exercise with a set before importing."
            return
        }
        errorMessage = nil
        let toImport = draftApplyingResolutions(draft)
        celebration = computeCelebration(for: [toImport], in: context)
        let origin = sessions.first?.kind.originName
        do {
            let summary = try importHandler?(toImport, externalID, context)
                ?? WorkoutScanImporter.import(
                    toImport,
                    externalID: externalID,
                    source: .textEntry,
                    originName: origin,
                    in: context
                )
            finishCommit(summary: summary)
            refreshSystemSurfaces(after: summary, in: context)
        } catch {
            errorMessage = "Couldn't save the workout. Please try again."
            MarbleHaptics.error()
        }
    }

    func commitSelected(into context: ModelContext) {
        persistOpenReview()
        guard unresolvedSessionCount == 0 else {
            errorMessage = "Review each workout that Marble couldn't read before adding this batch."
            return
        }
        let selected = importableSelectedSessions
        guard !selected.isEmpty else {
            if alreadyImportedSessionCount > 0 {
                finishCommit(summary: WorkoutImporter.Summary(skipped: alreadyImportedSessionCount))
                return
            }
            errorMessage = "Select at least one workout that isn't already in your journal."
            return
        }
        errorMessage = nil
        let items = selected.map { session in
            (draftApplyingResolutions(session.draft), session.externalID)
        }
        celebration = computeCelebration(for: items.map(\.0), in: context)
        do {
            let summary: WorkoutImporter.Summary
            if let importHandler {
                var merged = WorkoutImporter.Summary()
                let exercisesBefore = WorkoutImporter.exerciseCount(in: context)
                for item in items {
                    let one = try importHandler(item.0, item.1, context)
                    merged.importedWorkouts += one.importedWorkouts
                    merged.importedSets += one.importedSets
                    merged.skipped += one.skipped
                    merged.createdExercises += one.createdExercises
                }
                if merged.createdExercises == 0 {
                    merged.createdExercises = max(0, WorkoutImporter.exerciseCount(in: context) - exercisesBefore)
                }
                summary = merged
            } else {
                summary = try WorkoutScanImporter.importAll(
                    selected.map {
                        (
                            draft: draftApplyingResolutions($0.draft),
                            externalID: $0.externalID,
                            originName: $0.kind.originName
                        )
                    },
                    source: .textEntry,
                    in: context
                )
            }
            finishCommit(summary: summary)
            refreshSystemSurfaces(after: summary, in: context)
        } catch {
            errorMessage = "Couldn't save the workouts. Please try again."
            MarbleHaptics.error()
        }
    }

    private func draftApplyingResolutions(_ draft: ParsedWorkoutDraft) -> ParsedWorkoutDraft {
        var toImport = draft
        for index in toImport.exercises.indices {
            let id = toImport.exercises[index].id
            guard let resolution = resolutions[id] else { continue }
            switch resolution.choice {
            case let .library(libraryID, name):
                toImport.exercises[index].name = name
                toImport.exercises[index].libraryExerciseID = libraryID
                toImport.exercises[index].createsNewLibraryExercise = false
            case .createNew:
                toImport.exercises[index].libraryExerciseID = nil
                // Bypass name reuse only when an exact row already exists and
                // the user explicitly selected "Create new" in review.
                let reviewedName = toImport.exercises[index].trimmedName
                toImport.exercises[index].createsNewLibraryExercise = resolution.suggestions.contains {
                    $0.candidate.name.caseInsensitiveCompare(reviewedName) == .orderedSame
                }
            }
        }
        return toImport
    }

    private func finishCommit(summary: WorkoutImporter.Summary) {
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
        if summary.createdExercises > 0 {
            Task { await ExerciseSpotlightIndex.refreshAfterLibraryChange() }
        }
        // The imported result no longer has unsaved source text. Clearing it
        // prevents a later Shortcut handoff from appending the saved workout
        // and importing the same sets again under a new content hash.
        text = ""
        phase = .imported
    }

    /// Text entry is now Marble's primary logging path, so its successful saves
    /// must refresh the same widget, reminder, and Health surfaces as App Intents.
    private func refreshSystemSurfaces(after summary: WorkoutImporter.Summary, in context: ModelContext) {
        guard summary.importedSets > 0 else { return }
        Task {
            await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)
            await HealthSessionExporter.shared.exportIfEnabled(from: context)
        }
    }

    /// Back to the input step keeping the text, so a bad parse is editable.
    func editText() {
        persistOpenReview()
        phase = .input
        errorMessage = nil
        reviewingSessionID = nil
    }

    /// Volume + PR detection for the imported screen. Pure lookups against the
    /// same tested record engine the journal uses; runs pre-import so "records
    /// to beat" means records on file before this workout.
    private func computeCelebration(for drafts: [ParsedWorkoutDraft], in context: ModelContext) -> ImportCelebration {
        var volumeKilograms = 0.0
        var prExercises: [String] = []

        for draft in drafts {
            for exercise in draft.importableExercises {
                for set in exercise.sets {
                    if let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 {
                        volumeKilograms += PersonalRecords.kilograms(weight, unit: set.weightUnit) * Double(reps)
                    }
                }

                // Only an existing library exercise has records to beat; a freshly
                // created one is celebrated as "new in your library" instead.
                let name = exercise.trimmedName
                let existing: Exercise?
                if let selectedID = exercise.libraryExerciseID {
                    var descriptor = FetchDescriptor<Exercise>(
                        predicate: #Predicate { $0.id == selectedID }
                    )
                    descriptor.fetchLimit = 1
                    existing = (try? context.fetch(descriptor))?.first
                } else if exercise.createsNewLibraryExercise {
                    existing = nil
                } else {
                    var descriptor = FetchDescriptor<Exercise>(
                        predicate: #Predicate { $0.name == name }
                    )
                    descriptor.fetchLimit = 1
                    existing = (try? context.fetch(descriptor))?.first
                }
                guard let existing else { continue }
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
                if beatsRecord, !prExercises.contains(existing.name) {
                    prExercises.append(existing.name)
                }
            }
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
        unparsedLineIDs = []
        retryingUnparsedLineIDs = []
        sessions = []
        reviewingSessionID = nil
        batchProgress = nil
        livePreview = nil
        parseStage = .readingNotation
        celebration = ImportCelebration(volumeText: nil, prExercises: [])
    }

    /// Starts a fresh root-tab draft from a Shortcut or deep-link handoff.
    /// This is an explicit user action, so replacing any previous root draft is
    /// less surprising than silently appending unrelated workouts together.
    func startNewWorkout(with initialText: String) {
        reset()
        text = initialText
    }
}
