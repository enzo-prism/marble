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

    /// Has this exact scan (same image hash) already been imported?
    static func alreadyImported(externalID: String, in context: ModelContext) throws -> Bool {
        let key = ImportedWorkout.deduplicationKey(source: .photoScan, externalID: externalID)
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
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> WorkoutImporter.Summary {
        var summary = WorkoutImporter.Summary()

        let exercises = draft.importableExercises
        guard !exercises.isEmpty else { return summary }

        if try alreadyImported(externalID: externalID, in: context) {
            summary.skipped = 1
            return summary
        }

        let performedAt = draft.performedAt ?? AppEnvironment.now
        var setCount = 0

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
                let entry = SetEntry(
                    exercise: resolved,
                    performedAt: performedAt,
                    weight: set.weight,
                    weightUnit: set.weightUnit,
                    reps: set.reps,
                    distance: set.distance,
                    distanceUnit: set.distanceUnit,
                    durationSeconds: set.durationSeconds,
                    restAfterSeconds: resolved.defaultRestSeconds,
                    notes: importNote
                )
                context.insert(entry)
                setCount += 1
            }
        }

        let ledger = ImportedWorkout(
            source: .photoScan,
            externalID: externalID,
            title: draft.title,
            workoutDate: performedAt,
            setsImported: setCount
        )
        context.insert(ledger)

        do {
            try save(context)
        } catch {
            context.rollback()
            throw WorkoutImporterError.saveFailed
        }

        summary.importedWorkouts = 1
        summary.importedSets = setCount
        return summary
    }

    /// Cardio/timed-only movements rest 0; anything with load or reps gets a sane
    /// strength default.
    private static func defaultRestSeconds(for profile: ExerciseMetricsProfile) -> Int {
        (profile.usesWeight || profile.usesReps) ? 90 : 0
    }
}
