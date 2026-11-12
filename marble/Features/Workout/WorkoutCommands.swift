import AppIntents
import Foundation
import SwiftData

/// The mutations shared by voice, system controls and interactive workout UI.
/// Persistence always precedes timers, donations and system-surface publication.
@MainActor
enum WorkoutCommands {
    static var preferredWeightUnit: WeightUnit? {
        SharedDefaults.suite.string(forKey: SharedDefaults.Key.preferredWeightUnit).flatMap(WeightUnit.init(rawValue:))
    }
    nonisolated static func initialWeightUnit(preference: WeightUnit?, lastEntryUnit: WeightUnit?) -> WeightUnit {
        lastEntryUnit ?? preference ?? .lb
    }

    struct LogRequest {
        var exerciseID: UUID
        var exerciseName: String
        var reps: Int?
        var weight: Double?
        var unit: WeightUnit?
        var distance: Double?
        var distanceUnit: DistanceUnit?
        var durationSeconds: Double?
        var performedAt: Date?
        var effort: Int?
        var notes: String?

        var isValid: Bool {
            (reps.map { (0...100_000).contains($0) } ?? true)
                && (weight.map { $0.isFinite && (0...1_000_000).contains($0) } ?? true)
                && (distance.map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } ?? true)
                && (durationSeconds.map { $0.isFinite && $0 >= 0.1 && $0 <= 86_400 } ?? true)
                && (effort.map { (1...10).contains($0) } ?? true)
                && (performedAt.map { $0 <= AppEnvironment.now.addingTimeInterval(60) } ?? true)
        }
    }

    struct Outcome {
        let entry: SetEntry?
        let message: String
    }

    static func log(_ request: LogRequest, undoManager: UndoManager? = nil) async throws -> Outcome {
        guard request.isValid else {
            return Outcome(entry: nil, message: "Check the set's numbers and try again. Duration must be positive and no longer than 24 hours.")
        }
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let exerciseID = request.exerciseID
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })
        guard let model = (try? context.fetch(descriptor))?.first else {
            return Outcome(entry: nil, message: "Couldn't find \(request.exerciseName) in Marble.")
        }

        let metrics = model.metrics
        let lastEntry = SetEntryQueries.mostRecentEntry(for: exerciseID, in: context)

        // Unit precedence, unchanged from AddSetView: an explicitly spoken unit wins,
        // then the unit this exercise was last logged in, then the Settings default,
        // then `.lb`. Never guess a unit for a number that came from elsewhere.
        let resolvedUnit = request.unit ?? WorkoutCommands.initialWeightUnit(
            preference: WorkoutCommands.preferredWeightUnit,
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
            return WorkoutCommands.convert(inherited, from: lastEntry.weightUnit, to: resolvedUnit)
        }()
        let resolvedInputWeight: Double? = request.weight ?? inheritedInputWeight
        let storedWeight: Double? = metrics.usesWeight ? model.storedWeight(from: resolvedInputWeight) : nil

        let resolvedReps: Int? = metrics.usesReps ? (request.reps ?? lastEntry?.reps) : nil
        // Distance can repeat a course length. A measured time must be supplied for
        // each effort; silently copying the last performance invents a new result.
        let resolvedDistanceUnit: DistanceUnit = request.distanceUnit ?? lastEntry?.distanceUnit ?? model.preferredDistanceUnit
        let inheritedDistance = lastEntry?.distance.map { lastEntry!.distanceUnit.meters(from: $0) / resolvedDistanceUnit.metersPerUnit }
        let resolvedDistance: Double? = metrics.usesDistance ? (request.distance ?? inheritedDistance) : nil
        let tenths = request.durationSeconds.map { SprintTiming.tenths(fromSeconds: $0) }
        let resolvedDuration: Int? = metrics.usesDuration ? tenths.map { max(1, SprintTiming.wholeSeconds(fromTenths: $0)) } : nil

        // A required metric with nothing to fill it from is a bad row. Say so instead
        // of writing a set that pollutes volume, PRs and trends.
        let missing = WorkoutCommands.missingRequiredMetrics(
            metrics: metrics,
            storedWeight: storedWeight,
            reps: resolvedReps,
            distance: resolvedDistance,
            durationSeconds: resolvedDuration
        )
        guard missing.isEmpty else {
            let needed = WorkoutCommands.formattedList(missing)
            let message = "\(model.name) needs \(needed), and there's no earlier set to copy from."
                + " Try again with the details, or open Marble to log it."
            return Outcome(entry: nil, message: "\(message)")
        }

        let now = AppEnvironment.now
        let performedAt = request.performedAt ?? now
        let entry = SetEntry(
            exercise: model,
            performedAt: performedAt,
            weight: storedWeight,
            weightUnit: resolvedUnit,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: resolvedDistanceUnit,
            durationSeconds: resolvedDuration,
            difficulty: request.effort ?? lastEntry?.difficulty ?? 8,
            restAfterSeconds: lastEntry?.restAfterSeconds ?? model.defaultRestSeconds,
            // Notes are intentionally NOT inherited: a note about a previous set
            // silently reattached to a new one reads as a lie in the journal.
            notes: request.notes,
            createdAt: now,
            updatedAt: now
        )

        // PR detection runs against history *excluding* this set, then asks the real
        // engine what the set earned. Both calls canonicalize to kg internally, which
        // is why nothing here compares raw weights.
        let history = WorkoutCommands.history(for: exerciseID, in: context)
        let records = PersonalRecords.records(for: model, entries: history)
        let beatsExisting = PersonalRecords.projectedBadge(
            storedWeight: metrics.usesWeight ? storedWeight : nil,
            weightUnit: resolvedUnit,
            reps: metrics.usesReps ? resolvedReps : nil,
            beating: records,
            metrics: metrics
        )
        let earned: PersonalRecordBadge = PersonalRecords.badges(for: history + [entry])[entry.id] ?? []

        let candidateSession = WorkoutSessionIntentSupport.activeSession(in: context)
        let activeSession = candidateSession.flatMap { session in
            Calendar.current.isDate(performedAt, inSameDayAs: now) && performedAt >= session.startedAt.addingTimeInterval(-60) ? session : nil
        }
        let sprintSnapshot = WorkoutCommands.sprintSnapshot(
            for: model,
            entry: entry,
            lastEntry: lastEntry,
            session: activeSession,
            in: context
        )

        let detail: SprintRepDetail? = {
            if let value = WorkoutCommands.sprintDetail(for: model, entry: entry, in: context) {
                if let tenths { value.durationTenths = tenths }
                return value
            }
            guard metrics.usesDuration, let tenths else { return nil }
            return SprintRepDetail(setEntryID: entry.id, durationTenths: tenths,
                targetLowerTenths: 0, targetUpperTenths: 0, createdAt: now)
        }()
        guard commit(entry, session: activeSession, snapshot: sprintSnapshot, detail: detail, in: context) else {
            return Outcome(entry: nil, message: "Couldn't log that set. Open Marble to try again.")
        }

        // Only after a successful save: the widget must never advertise a row
        // that was rolled back, and a refused log (the guards above) must not
        // re-stamp the snapshot as fresh either.
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [model.id])

        // A voice-logged set is now undoable the way an in-app one is (see
        // `IntentUndo`).
        IntentUndo.registerLoggedSet(
            entryID: entry.id,
            goalSnapshotID: sprintSnapshot?.id,
            container: try AppIntentsSupport.resolvedContainer(),
            undoManager: undoManager,
            actionName: "Log Set"
        )

        let summary = WorkoutCommands.summary(
            exercise: model,
            metrics: metrics,
            storedWeight: storedWeight,
            unit: resolvedUnit,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: resolvedDistanceUnit,
            durationSeconds: resolvedDuration,
            beatsExisting: beatsExisting,
            earned: earned,
            durationTenths: tenths
        )
        if Calendar.current.isDate(performedAt, inSameDayAs: now) {
            await RestActivityController.shared.waitForPendingLiveActivityOperation()
        }
        return Outcome(entry: entry, message: summary)
    }

    @discardableResult
    static func commit(_ entry: SetEntry, session: WorkoutSession?, snapshot: SprintGoalSnapshot? = nil,
        detail: SprintRepDetail? = nil, variantID: UUID? = nil, in context: ModelContext) -> Bool {
        context.insert(entry)
        if let snapshot { context.insert(snapshot) }
        if let detail { context.insert(detail) }
        if let variantID {
            if let variant = try? context.fetch(FetchDescriptor<SprintVariant>(predicate: #Predicate { $0.id == variantID })).first {
                variant.lastUsedAt = entry.createdAt
            }
            SprintVariant.syncLegacyPrescription(for: entry.exercise.id, in: context)
        }
        let isCurrentDay = Calendar.current.isDate(entry.performedAt, inSameDayAs: AppEnvironment.now)
        if isCurrentDay, let session, session.isActive, entry.performedAt >= session.startedAt.addingTimeInterval(-60) {
            session.append(entry, at: entry.createdAt)
        }
        guard context.saveOrRollback() else { return false }
        let isLive = abs(entry.performedAt.timeIntervalSince(AppEnvironment.now)) <= 60
        if isLive { RestActivityController.shared.startRest(for: entry) }
        return true
    }

    static func donateLoggedExercise(_ entry: SetEntry) {
        guard !TestHooks.isUITesting,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        var intent = LogSetIntent()
        intent.exercise = ExerciseEntity(entry.exercise)
        Task { try? await intent.donate() }
    }

    @discardableResult
    static func repeatSet(_ source: SetEntry, into session: WorkoutSession?, requestID: UUID? = nil, in context: ModelContext) -> SetEntry? {
        let now = AppEnvironment.now
        let duplicate = source.duplicated(at: now)
        if let requestID { duplicate.id = requestID }
        context.insert(duplicate)
        SetLogging.copySprintMetadata(from: source, to: duplicate, in: context)
        guard commit(duplicate, session: session, in: context) else { return nil }
        return duplicate
    }

    static func latestRepeatSource(in context: ModelContext) throws -> SetEntry? {
        if let session = WorkoutSessionIntentSupport.activeSession(in: context) {
            return session.orderedEntries.last
        }
        let now = AppEnvironment.now
        var descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.performedAt <= now },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func start(in context: ModelContext, title: String? = nil, requestID: UUID? = nil) -> WorkoutSession? {
        if let existing = WorkoutSessionIntentSupport.activeSession(in: context) { return existing }
        let now = AppEnvironment.now
        let session = WorkoutSession(title: title ?? WorkoutSessionIntentSupport.suggestedTitle(in: context), startedAt: now, createdAt: now, updatedAt: now)
        if let requestID { session.id = requestID }
        context.insert(session)
        guard context.saveOrRollback() else { return nil }
        return session
    }

    @discardableResult
    static func finish(_ session: WorkoutSession, in context: ModelContext) -> Bool {
        guard session.isActive else { return true }
        session.finish()
        guard context.saveOrRollback() else { return false }
        RestActivityController.shared.cancelRest()
        return true
    }
}
