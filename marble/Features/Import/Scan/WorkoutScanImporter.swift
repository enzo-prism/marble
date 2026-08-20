import Foundation
import SwiftData

/// Commits a reviewed `ParsedWorkoutDraft` to the journal.
///
/// This is the scan equivalent of `WorkoutImporter`: it reuses the same exercise
/// resolution (`WorkoutImportMapper.resolveExercise`, case-insensitive name match or
/// create), the same `ImportedWorkout` dedup ledger, and the same all-or-nothing save.
/// It does *not* go through `WorkoutImportRecord`, because a handwritten page mixes
/// strength, bodyweight, timed, and cardio movements in one session — richer than the
/// strength-or-cardio `WorkoutImportRecord` shape — and a scanned page maps to a single
/// dedup entry rather than one record per remote activity.
enum WorkoutScanImporter {

    static let importNote = "Imported from a scanned workout"
    static let textEntryNote = "Imported from Paste or Type"

    /// Millisecond spacing of the review-order cascade (see `import`). 1 ms per
    /// set keeps even a 200-set paste inside one-fifth of a second.
    static let orderPreservationStep: TimeInterval = 0.001

    static func note(for source: ImportSource) -> String {
        source == .textEntry ? textEntryNote : importNote
    }

    /// Has this exact scan (same image hash) or typed text (same content hash)
    /// already been imported?
    static func alreadyImported(externalID: String, source: ImportSource = .photoScan, in context: ModelContext) throws -> Bool {
        let key = ImportedWorkout.deduplicationKey(source: source, externalID: externalID)
        var descriptor = FetchDescriptor<ImportedWorkout>(
            predicate: #Predicate<ImportedWorkout> { $0.deduplicationKey == key }
        )
        descriptor.fetchLimit = 1
        return !(try context.fetch(descriptor)).isEmpty
    }

    /// Persist the draft. `externalID` is a stable identity for the captured image
    /// (a content hash) so re-importing the identical photo is a no-op.
    @discardableResult
    static func `import`(
        _ draft: ParsedWorkoutDraft,
        externalID: String,
        source: ImportSource = .photoScan,
        originName: String? = nil,
        attachSession: Bool = true,
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> WorkoutImporter.Summary {
        var summary = WorkoutImporter.Summary()

        let exercises = draft.importableExercises
        guard !exercises.isEmpty else { return summary }

        if try alreadyImported(externalID: externalID, source: source, in: context) {
            summary.skipped = 1
            return summary
        }

        let performedAt = draft.performedAt ?? AppEnvironment.now
        let exercisesBefore = WorkoutImporter.exerciseCount(in: context)
        var setCount = 0
        var createdEntries: [SetEntry] = []

        // Review-order preservation: imported sets usually share one workout-level
        // date, and the journal sorts by `performedAt` descending — ties come back
        // in undefined storage order, scrambling multi-exercise workouts. Give the
        // sets a deterministic millisecond cascade so the first set of the reviewed
        // draft is the newest and the journal lists the workout exactly as reviewed.
        // The cascade steps *forward* from the effective date, so a date-only pick
        // (midnight) never pushes sets into the previous day, and the whole span
        // stays sub-second: invisible at minute display precision and far below any
        // explicit per-set time gap, so real timestamps still win.
        let totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        var setOrdinal = 0

        for exercise in exercises {
            let name = exercise.trimmedName
            let profile = exercise.metricsProfile
            let resolved = try WorkoutImportMapper.resolveExercise(
                name: name,
                category: WorkoutImportMapper.inferredCategory(for: name),
                metrics: profile,
                defaultRestSeconds: defaultRestSeconds(for: profile),
                in: context
            )

            for set in exercise.sets {
                let orderedDate = (set.performedAt ?? performedAt)
                    .addingTimeInterval(Self.orderPreservationStep * Double(totalSets - 1 - setOrdinal))
                setOrdinal += 1
                let entry = SetEntry(
                    exercise: resolved,
                    performedAt: orderedDate,
                    weight: set.weight,
                    weightUnit: set.weightUnit,
                    reps: set.reps,
                    distance: set.distance,
                    distanceUnit: set.distanceUnit,
                    durationSeconds: set.durationSeconds,
                    difficulty: set.difficulty ?? 8,
                    restAfterSeconds: set.restSeconds ?? resolved.defaultRestSeconds,
                    notes: composedNote(source: source, originName: originName, userNote: set.notes)
                )
                context.insert(entry)
                createdEntries.append(entry)
                setCount += 1
            }
        }

        // The ledger's date must match what actually landed in the journal:
        // with per-set overrides in play that is the earliest effective set
        // date, not necessarily the workout-level date.
        let ledgerDate = exercises
            .flatMap(\.sets)
            .map { $0.performedAt ?? performedAt }
            .min() ?? performedAt
        let ledger = ImportedWorkout(
            source: source,
            externalID: externalID,
            title: draft.title,
            workoutDate: ledgerDate,
            setsImported: setCount,
            originName: originName,
            durationSeconds: sessionDurationSeconds(
                draft: draft,
                startedAt: createdEntries.map(\.performedAt).min() ?? ledgerDate
            )
        )
        context.insert(ledger)
        // Same contract as `WorkoutImporter`: journal badges and set-detail
        // provenance walk `SetEntry.importedWorkout`. Leaving this nil was why
        // typed/scan sets never showed an origin badge.
        for entry in createdEntries {
            entry.importedWorkout = ledger
        }

        if attachSession, !createdEntries.isEmpty {
            let startedAt = createdEntries.map(\.performedAt).min() ?? ledgerDate
            let cascadeEnd = createdEntries.map(\.performedAt).max() ?? startedAt
            let endedAt = sessionEndedAt(draft: draft, startedAt: startedAt, cascadeEnd: cascadeEnd)
            let sessionTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = WorkoutSession(
                title: sessionTitle.isEmpty ? "Imported workout" : sessionTitle,
                startedAt: startedAt,
                endedAt: max(endedAt, startedAt),
                notes: composedNote(source: source, originName: originName, userNote: draft.notes),
                entries: createdEntries
            )
            context.insert(session)
        }

        do {
            try save(context)
        } catch {
            context.rollback()
            throw WorkoutImporterError.saveFailed
        }

        summary.importedWorkouts = 1
        summary.importedSets = setCount
        // Scanned workouts create library rows just as often as Health imports
        // do, so they owe the same Spotlight/Siri refresh signal.
        summary.createdExercises = max(0, WorkoutImporter.exerciseCount(in: context) - exercisesBefore)
        return summary
    }

    /// Commits several reviewed drafts in one save. Each draft keeps its own
    /// dedup identity so one day of a week-long paste can be skipped independently.
    @discardableResult
    static func importAll(
        _ items: [(draft: ParsedWorkoutDraft, externalID: String, originName: String?)],
        source: ImportSource = .textEntry,
        attachSession: Bool = true,
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> WorkoutImporter.Summary {
        var summary = WorkoutImporter.Summary()
        let exercisesBefore = WorkoutImporter.exerciseCount(in: context)
        for item in items {
            let one = try `import`(
                item.draft,
                externalID: item.externalID,
                source: source,
                originName: item.originName,
                attachSession: attachSession,
                in: context,
                save: { _ in }
            )
            summary.importedWorkouts += one.importedWorkouts
            summary.importedSets += one.importedSets
            summary.skipped += one.skipped
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw WorkoutImporterError.saveFailed
        }
        summary.createdExercises = max(0, WorkoutImporter.exerciseCount(in: context) - exercisesBefore)
        return summary
    }

    /// Cardio/timed-only movements rest 0; anything with load or reps gets a sane
    /// strength default.
    private static func defaultRestSeconds(for profile: ExerciseMetricsProfile) -> Int {
        (profile.usesWeight || profile.usesReps) ? 90 : 0
    }

    private static func journalNote(source: ImportSource, originName: String?) -> String {
        switch originName {
        case "Hevy": return "Imported from Hevy"
        case "Strong": return "Imported from Strong"
        default: return note(for: source)
        }
    }

    /// Provenance plus the source's own note. User text wins the second clause;
    /// a blank note stays provenance-only so scan/typed sets match the old copy.
    static func composedNote(source: ImportSource, originName: String?, userNote: String?) -> String {
        let provenance = journalNote(source: source, originName: originName)
        let trimmed = userNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return provenance }
        if trimmed.localizedCaseInsensitiveContains(provenance) { return trimmed }
        return "\(provenance). \(trimmed)"
    }

    /// Wall-clock session length from the export. The millisecond cascade is
    /// not a duration — leave the ledger nil when the source didn't state one.
    private static func sessionDurationSeconds(draft: ParsedWorkoutDraft, startedAt: Date) -> Int? {
        if let duration = draft.durationSeconds, duration > 0 { return duration }
        if let endedAt = draft.endedAt {
            let seconds = Int(endedAt.timeIntervalSince(startedAt).rounded())
            return seconds > 0 ? seconds : nil
        }
        return nil
    }

    private static func sessionEndedAt(draft: ParsedWorkoutDraft, startedAt: Date, cascadeEnd: Date) -> Date {
        if let endedAt = draft.endedAt, endedAt > startedAt { return endedAt }
        if let duration = draft.durationSeconds, duration > 0 {
            return startedAt.addingTimeInterval(TimeInterval(duration))
        }
        return max(cascadeEnd, startedAt)
    }
}
