import Foundation
import SwiftData

/// Exact-ID edits to one confirmed manual set, shared by `CorrectLoggedSetIntent`
/// and the interactive logged-set snippet buttons.
///
/// Every operation addresses a set by its stable `SetEntry.id` and never falls back
/// to "the latest set": a stale card or a delayed tap must miss rather than change an
/// unrelated row. Imported (Apple Health / Strava) rows are refused — their source of
/// truth lives outside Marble. Persistence always precedes rest-timer and
/// system-surface updates.
extension WorkoutCommands {
    /// Values to change on a confirmed set. `nil` leaves a field unchanged.
    struct Correction {
        var reps: Int?
        var weight: Double?
        var unit: WeightUnit?
        var distance: Double?
        var distanceUnit: DistanceUnit?
        var durationSeconds: Double?
        var effort: Int?
        var notes: String?
    }

    /// One tap's load increase for a set recorded in `unit`: 5 lb or 2.5 kg, applied
    /// to the input weight (one dumbbell for a dumbbell pair), like the logger field.
    nonisolated static func weightIncrement(for unit: WeightUnit) -> Double {
        switch unit {
        case .lb: return 5
        case .kg: return 2.5
        }
    }

    /// The manual set with exactly this ID, or `nil` when it no longer exists or was
    /// imported from another app.
    static func manualEntry(id: UUID, in context: ModelContext) -> SetEntry? {
        guard let entry = try? context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == id })).first,
              entry.importedWorkout == nil else { return nil }
        return entry
    }

    /// Applies `correction` in place to the set with exactly `entryID`, then refreshes
    /// system surfaces. Throws a user-facing `WorkoutIntentFailure` without writing
    /// when the set is gone, a value is invalid, or the exercise lacks that metric.
    @discardableResult
    static func correct(entryID id: UUID, _ correction: Correction) async throws -> SetEntry {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let entry = manualEntry(id: id, in: context) else {
            throw WorkoutIntentFailure(message: "That manual set is no longer available. Open Marble to choose a set.")
        }
        let request = LogRequest(exerciseID: entry.exercise.id, exerciseName: entry.exercise.name,
            reps: correction.reps, weight: correction.weight, unit: correction.unit,
            distance: correction.distance, distanceUnit: correction.distanceUnit,
            durationSeconds: correction.durationSeconds, effort: correction.effort, notes: correction.notes)
        guard request.isValid else { throw WorkoutIntentFailure(message: "Check the corrected values and try again.") }
        let metrics = entry.exercise.metrics
        guard (correction.reps == nil || metrics.usesReps),
              (correction.weight == nil && correction.unit == nil || metrics.usesWeight),
              (correction.distance == nil && correction.distanceUnit == nil || metrics.usesDistance),
              (correction.durationSeconds == nil || metrics.usesDuration) else {
            throw WorkoutIntentFailure(message: "This exercise doesn't use one of those metrics. Open Marble to check the exercise settings.")
        }
        if correction.weight != nil || correction.unit != nil {
            let targetUnit = correction.unit ?? entry.weightUnit
            let inherited = entry.exercise.displayedWeightInput(from: entry.weight).map {
                convert($0, from: entry.weightUnit, to: targetUnit)
            }
            entry.weight = entry.exercise.storedWeight(from: correction.weight ?? inherited)
            entry.weightUnit = targetUnit
        }
        if let reps = correction.reps { entry.reps = reps }
        if let distanceUnit = correction.distanceUnit {
            if correction.distance == nil, let previous = entry.distance {
                entry.distance = entry.distanceUnit.meters(from: previous) / distanceUnit.metersPerUnit
            }
            entry.distanceUnit = distanceUnit
        }
        if let distance = correction.distance { entry.distance = distance }
        if let durationSeconds = correction.durationSeconds {
            let tenths = SprintTiming.tenths(fromSeconds: durationSeconds)
            entry.durationSeconds = max(1, SprintTiming.wholeSeconds(fromTenths: tenths))
            if let detail = try context.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == id })).first {
                detail.durationTenths = tenths
            } else {
                context.insert(SprintRepDetail(setEntryID: id, durationTenths: tenths, targetLowerTenths: 0, targetUpperTenths: 0))
            }
        }
        if let effort = correction.effort { entry.difficulty = effort }
        if let notes = correction.notes { entry.notes = notes.isEmpty ? nil : notes }
        entry.updatedAt = AppEnvironment.now
        guard context.saveOrRollback() else { throw WorkoutIntentFailure(message: "Marble couldn't save that correction.") }
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [entry.exercise.id])
        return entry
    }

    /// Adds one load step (5 lb / 2.5 kg in the set's own unit) to exactly this set.
    @discardableResult
    static func addWeightStep(toEntryID id: UUID) async throws -> SetEntry {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let entry = manualEntry(id: id, in: context) else {
            throw WorkoutIntentFailure(message: "That manual set is no longer available. Open Marble to choose a set.")
        }
        guard entry.exercise.metrics.usesWeight else {
            throw WorkoutIntentFailure(message: "This exercise doesn't track weight.")
        }
        let current = entry.exercise.displayedWeightInput(from: entry.weight) ?? 0
        let next = current + weightIncrement(for: entry.weightUnit)
        return try await correct(entryID: id, Correction(weight: next, unit: entry.weightUnit))
    }

    /// Adds one rep to exactly this set.
    @discardableResult
    static func addRep(toEntryID id: UUID) async throws -> SetEntry {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let entry = manualEntry(id: id, in: context) else {
            throw WorkoutIntentFailure(message: "That manual set is no longer available. Open Marble to choose a set.")
        }
        guard entry.exercise.metrics.usesReps else {
            throw WorkoutIntentFailure(message: "This exercise doesn't track reps.")
        }
        return try await correct(entryID: id, Correction(reps: (entry.reps ?? 0) + 1))
    }

    /// Logs another set identical to exactly this confirmed set — the same copy
    /// semantics as Repeat Last Set, including precise sprint timing — into the
    /// running workout. The source must still exist; nothing is guessed.
    static func repeatConfirmedSet(entryID id: UUID) async throws -> SetEntry {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let source = manualEntry(id: id, in: context) else {
            throw WorkoutIntentFailure(message: "That manual set is no longer available. Open Marble to choose a set.")
        }
        guard let duplicate = repeatSet(source, into: WorkoutSessionIntentSupport.activeSession(in: context), in: context) else {
            throw WorkoutIntentFailure(message: "Couldn't log the set. Open Marble to try again.")
        }
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [source.exercise.id])
        return duplicate
    }

    /// Deletes exactly this manual set with its sprint goal and timing companions,
    /// cancels only the rest it started, and refreshes system surfaces. Returns
    /// `false` (without writing) when the set no longer exists.
    @discardableResult
    static func deleteConfirmedSet(entryID id: UUID) async throws -> Bool {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let exerciseID = removeSetRows(entryID: id, goalSnapshotID: nil, in: context) else { return false }
        guard context.saveOrRollback() else { throw WorkoutIntentFailure(message: "Marble couldn't remove that set.") }
        RestActivityController.shared.cancelRest(startedBy: id)
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [exerciseID])
        return true
    }

    /// Marks a manual set and its companions deleted without saving. Returns the
    /// set's exercise ID, or `nil` when no such manual set exists.
    ///
    /// `WorkoutSession.entries` is a one-way `.nullify` relationship with no inverse
    /// on `SetEntry`, so deleting the row is what drops it out of its session.
    static func removeSetRows(entryID id: UUID, goalSnapshotID: UUID?, in context: ModelContext) -> UUID? {
        guard let entry = manualEntry(id: id, in: context) else { return nil }
        let exerciseID = entry.exercise.id
        context.delete(entry)
        let goals = (try? context.fetch(FetchDescriptor<SprintGoalSnapshot>(predicate: #Predicate { $0.setEntryID == id }))) ?? []
        goals.forEach(context.delete)
        if let goalSnapshotID, !goals.contains(where: { $0.id == goalSnapshotID }),
           let goal = (try? context.fetch(FetchDescriptor<SprintGoalSnapshot>(predicate: #Predicate { $0.id == goalSnapshotID })))?.first {
            context.delete(goal)
        }
        let details = (try? context.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == id }))) ?? []
        details.forEach(context.delete)
        return exerciseID
    }
}
