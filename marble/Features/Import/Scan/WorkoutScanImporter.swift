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

        // Workouts are imported, never scheduled: the review picker is capped at
        // now, so a future draft date (an explicit future year) is saved as now,
        // matching what the picker showed.
        let now = AppEnvironment.now
        let performedAt = min(draft.performedAt ?? now, now)
        func effectiveDate(of set: ParsedSetDraft) -> Date {
            set.performedAt.map { min($0, now) } ?? performedAt
        }
        let exercisesBefore = WorkoutImporter.exerciseCount(in: context)
        var setCount = 0
        var createdEntries: [SetEntry] = []
        var exerciseResolver = WorkoutImportMapper.Resolver(in: context)

        // Review-order preservation: imported sets usually share one workout-level
        // date, and ties come back in undefined storage order, scrambling
        // multi-exercise workouts. Give the sets a deterministic millisecond
        // cascade in *chronological* order — the first reviewed set is the
        // earliest and the last ends exactly on the effective date — so session
        // detail, Repeat Workout, PR trails, and "latest set" all read the
        // workout the way it was done, exactly like manually logged sets. (It
        // used to run newest-first, which made Repeat reverse the workout on
        // every repeat.) Only sets sharing one effective date are spread, so a
        // set with its own explicit time keeps it exactly. The span stays
        // sub-second: invisible at minute display precision and far below any
        // explicit per-set time gap. It never starts before the date's local
        // day and never ends after the date, so an undated import stays at or
        // before "now".
        var groupSizes: [Date: Int] = [:]
        for set in exercises.flatMap(\.sets) {
            groupSizes[effectiveDate(of: set), default: 0] += 1
        }
        var groupOrdinals: [Date: Int] = [:]
        func cascaded(_ base: Date) -> Date {
            let ordinal = groupOrdinals[base, default: 0]
            groupOrdinals[base] = ordinal + 1
            let stepsBack = max((groupSizes[base] ?? 1) - 1 - ordinal, 0)
            guard stepsBack > 0 else { return base }
            // Just after midnight there may be less than the full span left in
            // the day: shrink the step so the group still ends on `base`
            // without spilling into the previous day.
            let available = base.timeIntervalSince(Calendar.current.startOfDay(for: base))
            let fullSpan = Self.orderPreservationStep * Double((groupSizes[base] ?? 1) - 1)
            let step = available >= fullSpan
                ? Self.orderPreservationStep
                : available / Double((groupSizes[base] ?? 1) - 1)
            guard step > 0 else {
                return base.addingTimeInterval(Self.orderPreservationStep * Double(ordinal))
            }
            return base.addingTimeInterval(-step * Double(stepsBack))
        }

        for exercise in exercises {
            let name = exercise.trimmedName
            let profile = exercise.metricsProfile
            let resolved = try exerciseResolver.resolve(
                name: name,
                category: WorkoutImportMapper.inferredCategory(for: name),
                metrics: profile,
                defaultRestSeconds: defaultRestSeconds(for: profile),
                libraryExerciseID: exercise.libraryExerciseID,
                createNew: exercise.createsNewLibraryExercise
            )

            for set in exercise.sets {
                let orderedDate = cascaded(effectiveDate(of: set))
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
        // the earliest saved set, which with per-set overrides in play is not
        // necessarily the workout-level date.
        let ledgerDate = createdEntries.map(\.performedAt).min() ?? performedAt
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
            let endedAt = sessionEndedAt(draft: draft, startedAt: startedAt, cascadeEnd: cascadeEnd, now: now)
            let sessionTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = WorkoutSession(
                title: sessionTitle.isEmpty ? "Imported workout" : sessionTitle,
                startedAt: startedAt,
                // A session can't end in the future: a stated duration from a
                // start moments ago stops at now.
                endedAt: max(min(endedAt, now), startedAt),
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

    private static func sessionEndedAt(draft: ParsedWorkoutDraft, startedAt: Date, cascadeEnd: Date, now: Date) -> Date {
        // An export's own end time is trusted only when it is in the past; a
        // clamped future draft falls back to its duration from the real start
        // (itself capped at now by the caller).
        if let endedAt = draft.endedAt, endedAt > startedAt, endedAt <= now { return endedAt }
        if let duration = draft.durationSeconds, duration > 0 {
            return startedAt.addingTimeInterval(TimeInterval(duration))
        }
        return max(cascadeEnd, startedAt)
    }
}
