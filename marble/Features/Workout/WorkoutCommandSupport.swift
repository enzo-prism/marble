import Foundation
import SwiftData

// MARK: - Helpers

extension WorkoutCommands {
    /// lb ↔ kg through `PersonalRecords.kilograms`, the single canonical factor in
    /// the app. Four production bugs in this repo came from moving a weight between
    /// units (or comparing across them) without going through kg — never inline a
    /// conversion factor here.
    nonisolated static func convert(_ value: Double, from source: WeightUnit, to target: WeightUnit) -> Double {
        guard source != target else { return value }
        let kilos = PersonalRecords.kilograms(value, unit: source)
        return kilos / PersonalRecords.kilograms(1, unit: target)
    }

    nonisolated static func missingRequiredMetrics(
        metrics: ExerciseMetricsProfile,
        storedWeight: Double?,
        reps: Int?,
        distance: Double?,
        durationSeconds: Int?
    ) -> [String] {
        var missing: [String] = []
        if metrics.weightIsRequired, (storedWeight ?? 0) <= 0 { missing.append("a weight") }
        if metrics.repsIsRequired, (reps ?? 0) <= 0 { missing.append("reps") }
        if metrics.distanceIsRequired, (distance ?? 0) <= 0 { missing.append("a distance") }
        if metrics.durationIsRequired, (durationSeconds ?? 0) <= 0 { missing.append("a duration") }
        return missing
    }

    nonisolated static func formattedList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last ?? "")"
        }
    }

    @MainActor
    static func history(for exerciseID: UUID, in context: ModelContext) -> [SetEntry] {
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise.id == exerciseID },
            sortBy: [SortDescriptor(\.performedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Freezes the goal this rep is actually being judged against.
    ///
    /// Prefers the exercise's **current** `SprintPrescription`, because copying the
    /// previous rep's snapshot is precisely the stale-freeze defect flagged on the
    /// Duplicate/Repeat/Siri paths: edit the prescription, log by voice, and the new
    /// rep gets scored against a target the athlete is no longer chasing.
    ///
    /// Copying the source rep's snapshot (the `LogLastSetAgainIntent` behaviour)
    /// remains as the fallback for when the prescription has since been deleted, so
    /// history keeps a goal rather than losing one.
    /// The tenths companion for a voice-logged sprint rep. Siri dictates whole
    /// seconds, so the recorded tenths are exact (×10); the frozen target comes
    /// from the exercise's primary `SprintVariant` at its full precision —
    /// the same plan the mirrored prescription snapshot above was rounded from.
    @MainActor
    static func sprintDetail(
        for exercise: Exercise,
        entry: SetEntry,
        in context: ModelContext
    ) -> SprintRepDetail? {
        guard let seconds = entry.durationSeconds, seconds > 0 else { return nil }
        let exerciseID = exercise.id
        let variantDescriptor = FetchDescriptor<SprintVariant>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        )
        guard let variants = try? context.fetch(variantDescriptor),
              let primary = SprintVariant.primary(for: exerciseID, in: variants) else { return nil }
        primary.lastUsedAt = entry.createdAt
        return SprintRepDetail(
            setEntryID: entry.id,
            durationTenths: SprintTiming.tenths(fromWholeSeconds: seconds),
            targetLowerTenths: primary.targetLowerTenths,
            targetUpperTenths: primary.targetUpperTenths,
            variantID: primary.id,
            createdAt: entry.createdAt
        )
    }

    @MainActor
    static func sprintSnapshot(
        for exercise: Exercise,
        entry: SetEntry,
        lastEntry: SetEntry?,
        session: WorkoutSession?,
        in context: ModelContext
    ) -> SprintGoalSnapshot? {
        let exerciseID = exercise.id
        let prescriptionDescriptor = FetchDescriptor<SprintPrescription>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        )
        if let prescription = (try? context.fetch(prescriptionDescriptor))?.first, prescription.isValid {
            // Same rep numbering as AddSetView: reps already in the running session,
            // plus this one. Outside a session we can't count reliably, so leave the
            // number off rather than assert a wrong one.
            let completed = session.map { runningSession in
                runningSession.entries.filter { $0.exercise.id == exerciseID }.count
            }
            let repetitionNumber: Int? = completed.flatMap { count in
                let next = count + 1
                return next <= prescription.repetitionCount ? next : nil
            }
            return SprintGoalSnapshot(
                setEntryID: entry.id,
                exerciseID: exerciseID,
                distance: prescription.distance,
                distanceUnit: exercise.preferredDistanceUnit,
                repetitionNumber: repetitionNumber,
                repetitionCount: prescription.repetitionCount,
                targetLowerSeconds: prescription.targetLowerSeconds,
                targetUpperSeconds: prescription.targetUpperSeconds,
                createdAt: entry.createdAt
            )
        }

        guard let lastEntry else { return nil }
        let lastID = lastEntry.id
        let goalDescriptor = FetchDescriptor<SprintGoalSnapshot>(
            predicate: #Predicate { $0.setEntryID == lastID }
        )
        guard let goal = (try? context.fetch(goalDescriptor))?.first else { return nil }
        return SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exerciseID,
            distance: goal.distance,
            distanceUnit: goal.distanceUnit,
            repetitionNumber: nil,
            repetitionCount: goal.repetitionCount,
            targetLowerSeconds: goal.targetLowerSeconds,
            targetUpperSeconds: goal.targetUpperSeconds,
            isInferred: goal.isInferred,
            createdAt: entry.createdAt
        )
    }

    /// Spoken confirmation. `formattedWeightSummary` is what keeps the dumbbell case
    /// honest out loud — "40 lb each (80 lb total)" rather than a bare 80.
    @MainActor
    static func summary(
        exercise: Exercise,
        metrics: ExerciseMetricsProfile,
        storedWeight: Double?,
        unit: WeightUnit,
        reps: Int?,
        distance: Double?,
        distanceUnit: DistanceUnit,
        durationSeconds: Int?,
        beatsExisting: PersonalRecordBadge,
        earned: PersonalRecordBadge,
        durationTenths: Int? = nil
    ) -> String {
        var parts: [String] = []
        if metrics.usesReps, let reps, reps > 0 {
            parts.append(reps == 1 ? "1 rep" : "\(reps) reps")
        }
        if metrics.usesWeight, let storedWeight, storedWeight > 0 {
            parts.append("at \(exercise.formattedWeightSummary(storedWeight, unit: unit))")
        }
        if metrics.usesDistance, let distance, distance > 0 {
            parts.append(exercise.formattedDistanceSummary(distance, unit: distanceUnit))
        }
        if metrics.usesDuration, let durationTenths {
            parts.append("for \(SprintTiming.text(tenths: durationTenths))")
        } else if metrics.usesDuration, let durationSeconds, durationSeconds > 0 {
            parts.append("for \(DateHelper.formattedDuration(seconds: durationSeconds))")
        }

        let detail = parts.isEmpty ? "" : " — \(parts.joined(separator: " "))"
        var message = "Logged \(exercise.name)\(detail)."

        if !beatsExisting.isEmpty {
            message += " \(beatsExisting.shortTitle) — a new personal best."
        } else if !earned.isEmpty {
            message += " That's your first \(exercise.name) best on record."
        }
        return message
    }
}
