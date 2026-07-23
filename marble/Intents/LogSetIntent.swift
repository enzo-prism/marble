import AppIntents
import Foundation
import SwiftData

// MARK: - Unit enum

/// `WeightUnit` as something Siri and the Shortcuts editor can offer.
///
/// Raw values match `WeightUnit` so the two can never drift, and so a saved
/// shortcut keeps meaning the same thing across releases.
nonisolated enum WeightUnitAppEnum: String, AppEnum, CaseIterable {
    case lb
    case kg

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Weight Unit" }

    static var caseDisplayRepresentations: [WeightUnitAppEnum: DisplayRepresentation] {
        [
            .lb: DisplayRepresentation(title: "Pounds", subtitle: "lb"),
            .kg: DisplayRepresentation(title: "Kilograms", subtitle: "kg")
        ]
    }

    var weightUnit: WeightUnit {
        switch self {
        case .lb: return .lb
        case .kg: return .kg
        }
    }

    init(_ unit: WeightUnit) {
        switch unit {
        case .lb: self = .lb
        case .kg: self = .kg
        }
    }
}

// MARK: - Intent

/// Logs one set of a named exercise, filling any gap from that exercise's history.
///
/// Every metric is optional so a spoken request can be as short as "log a set of
/// bench press in Marble" — the missing reps/weight/unit come from the most recent
/// set of the *same* exercise, which is the same idea as `LogLastSetAgainIntent`
/// but scoped to one movement instead of "whatever you did last".
struct LogSetIntent: AppIntent, PredictableIntent {
    static let title: LocalizedStringResource = "Log a Set of an Exercise"
    static let description = IntentDescription(
        "Logs a set of a specific exercise. Reps, weight and unit are copied from your last set of that exercise when you leave them out."
    )

    @Parameter(title: "Exercise", requestValueDialog: "Which exercise?")
    var exercise: ExerciseEntity

    @Parameter(title: "Reps")
    var reps: Int?

    /// The weight **as a human says it** — for a `singleDumbbellPair` exercise that
    /// is one dumbbell, exactly like the field in `AddSetView`. See `perform()`.
    @Parameter(title: "Weight")
    var weight: Double?

    @Parameter(title: "Unit")
    var unit: WeightUnitAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a set of \(\.$exercise)") {
            \.$reps
            \.$weight
            \.$unit
        }
    }

    /// `PredictableIntent`: every successful `perform()` teaches the system
    /// *when* this lifter logs *which* exercise, so Siri Suggestions and the
    /// Smart Stack can surface "Log a set of Bench Press" around actual
    /// training times — the personalised signal the widget's
    /// `TimelineEntryRelevance` heuristic cannot supply on its own.
    ///
    /// Only the exercise parameterises the prediction. Reps/weight/unit stay
    /// free on purpose: a predicted invocation then resolves through the same
    /// inherit-from-history path as a spoken request, instead of freezing one
    /// day's numbers into a suggestion.
    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$exercise) { exercise in
            DisplayRepresentation(
                title: "Log a set of \(exercise.name)",
                subtitle: "Reps and weight copied from your last set"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppIntentsSupport.resolvedContainer().mainContext
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })
        guard let model = (try? context.fetch(descriptor))?.first else {
            return .result(dialog: "Couldn't find \(exercise.name) in Marble.")
        }

        let metrics = model.metrics
        let lastEntry = SetEntryQueries.mostRecentEntry(for: exerciseID, in: context)

        // Unit precedence, unchanged from AddSetView: an explicitly spoken unit wins,
        // then the unit this exercise was last logged in, then the Settings default,
        // then `.lb`. Never guess a unit for a number that came from elsewhere.
        let resolvedUnit = unit?.weightUnit ?? AddSetView.initialWeightUnit(
            preference: AddSetView.preferredWeightUnit,
            lastEntryUnit: lastEntry?.weightUnit
        )

        // ── Dumbbell-pair safety ────────────────────────────────────────────────
        // Everything below works in *input* space (the number a human says) and is
        // converted to stored space exactly once, at the end, through
        // `model.storedWeight(from:)` — mirroring AddSetView's
        //     let storedWeight = exercise.storedWeight(from: resolvedWeight)
        // For a `singleDumbbellPair` exercise that doubles the value, so writing a
        // spoken "40" raw would halve the recorded volume, and re-writing an
        // inherited stored value raw would double it every single time.
        //
        // The inherited value therefore comes back out of storage through
        // `displayedWeightInput(from:)` (÷2) before re-entering it (×2) — an exact
        // round trip rather than a silent doubling.
        let inheritedInputWeight: Double? = {
            guard let lastEntry,
                  let inherited = model.displayedWeightInput(from: lastEntry.weight) else { return nil }
            return Self.convert(inherited, from: lastEntry.weightUnit, to: resolvedUnit)
        }()
        let resolvedInputWeight: Double? = weight ?? inheritedInputWeight
        let storedWeight: Double? = metrics.usesWeight ? model.storedWeight(from: resolvedInputWeight) : nil

        let resolvedReps: Int? = metrics.usesReps ? (reps ?? lastEntry?.reps) : nil
        // Distance/duration have no spoken parameter in 2.2, so they can only be
        // inherited — which is what keeps sprint and timed work loggable by voice.
        let resolvedDistance: Double? = metrics.usesDistance ? lastEntry?.distance : nil
        let resolvedDistanceUnit: DistanceUnit = lastEntry?.distanceUnit ?? model.preferredDistanceUnit
        let resolvedDuration: Int? = metrics.usesDuration ? lastEntry?.durationSeconds : nil

        // A required metric with nothing to fill it from is a bad row. Say so instead
        // of writing a set that pollutes volume, PRs and trends.
        let missing = Self.missingRequiredMetrics(
            metrics: metrics,
            storedWeight: storedWeight,
            reps: resolvedReps,
            distance: resolvedDistance,
            durationSeconds: resolvedDuration
        )
        guard missing.isEmpty else {
            let needed = Self.formattedList(missing)
            let message = "\(model.name) needs \(needed), and there's no earlier set to copy from."
                + " Try again with the details, or open Marble to log it."
            return .result(dialog: "\(message)")
        }

        let now = AppEnvironment.now
        let entry = SetEntry(
            exercise: model,
            performedAt: now,
            weight: storedWeight,
            weightUnit: resolvedUnit,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: resolvedDistanceUnit,
            durationSeconds: resolvedDuration,
            difficulty: lastEntry?.difficulty ?? 8,
            restAfterSeconds: lastEntry?.restAfterSeconds ?? model.defaultRestSeconds,
            // Notes are intentionally NOT inherited: a note about a previous set
            // silently reattached to a new one reads as a lie in the journal.
            notes: nil,
            createdAt: now,
            updatedAt: now
        )

        // PR detection runs against history *excluding* this set, then asks the real
        // engine what the set earned. Both calls canonicalize to kg internally, which
        // is why nothing here compares raw weights.
        let history = Self.history(for: exerciseID, in: context)
        let records = PersonalRecords.records(for: model, entries: history)
        let beatsExisting = PersonalRecords.projectedBadge(
            storedWeight: metrics.usesWeight ? storedWeight : nil,
            weightUnit: resolvedUnit,
            reps: metrics.usesReps ? resolvedReps : nil,
            beating: records,
            metrics: metrics
        )
        let earned: PersonalRecordBadge = PersonalRecords.badges(for: history + [entry])[entry.id] ?? []

        let activeSession = WorkoutSessionIntentSupport.activeSession(in: context)
        let sprintSnapshot = Self.sprintSnapshot(
            for: model,
            entry: entry,
            lastEntry: lastEntry,
            session: activeSession,
            in: context
        )

        context.insert(entry)
        if let sprintSnapshot { context.insert(sprintSnapshot) }
        // Voice-logged sets join the running workout, exactly as AddSetView does —
        // otherwise a Siri set silently falls outside the session it belongs to.
        activeSession?.append(entry, at: now)

        guard context.saveOrRollback() else {
            return .result(dialog: "Couldn't log that set. Open Marble to try again.")
        }

        // Only after a successful save: the widget must never advertise a row
        // that was rolled back, and a refused log (the guards above) must not
        // re-stamp the snapshot as fresh either.
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)

        let summary = Self.summary(
            exercise: model,
            metrics: metrics,
            storedWeight: storedWeight,
            unit: resolvedUnit,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: resolvedDistanceUnit,
            durationSeconds: resolvedDuration,
            beatsExisting: beatsExisting,
            earned: earned
        )
        return .result(dialog: "\(summary)")
    }
}

// MARK: - Helpers

extension LogSetIntent {
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
        earned: PersonalRecordBadge
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
        if metrics.usesDuration, let durationSeconds, durationSeconds > 0 {
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
