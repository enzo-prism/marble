import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct MarbleBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw MarbleBackupError.unreadableFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum MarbleBackupError: LocalizedError {
    case unreadableFile
    case unsupportedVersion(Int)
    case missingExercise(UUID)
    case missingSupplementType(UUID)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be read."
        case .unsupportedVersion(let version):
            return "This backup uses unsupported format version \(version)."
        case .missingExercise:
            return "The backup references an exercise that is missing."
        case .missingSupplementType:
            return "The backup references a supplement type that is missing."
        case .invalidPayload:
            return "The backup is incomplete or invalid."
        }
    }
}

struct MarbleBackupSummary: Equatable {
    let exercises: Int
    let sets: Int
    let supplementLogs: Int
    let sessions: Int
    let plans: Int
    /// Bodyweight / body-fat measurements. Surfaced because a silent zero here
    /// is exactly how months of weigh-ins went missing without anyone noticing.
    let bodyMetrics: Int
    /// Import-ledger rows (`ImportedWorkout`). This entity was dropped from the
    /// payload once already — after that restore, every re-import created
    /// duplicate journal entries because the dedup ledger came back empty.
    let importedWorkouts: Int
    /// Progress photo/video *metadata* rows only. The media binaries live on
    /// disk under `ProgressMediaStore` and are deliberately not in the JSON
    /// backup — see `ProgressMediaRecord`.
    let progressMedia: Int
    /// Weekday-bitmask reminder schedules (`CustomNotification`).
    let customNotifications: Int
}

@MainActor
enum MarbleBackupService {
    static let currentVersion = 1

    static func makeDocument(in context: ModelContext, now: Date? = nil) throws -> MarbleBackupDocument {
        let resolvedNow = now ?? AppEnvironment.now
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        let supplementTypes = try context.fetch(FetchDescriptor<SupplementType>())
        let supplementEntries = try context.fetch(FetchDescriptor<SupplementEntry>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let plans = try context.fetch(FetchDescriptor<SplitPlan>())
        let sprintPrescriptions = try context.fetch(FetchDescriptor<SprintPrescription>())
        let sprintGoalSnapshots = try context.fetch(FetchDescriptor<SprintGoalSnapshot>())
        // Schema V5. Omitting this is what silently threw away every weigh-in
        // on a phone-to-phone restore — the same class of bug as the dropped
        // `ImportedWorkout`. Any new @Model type belongs in this list, and
        // `MarbleBackupTests.testBackupPayloadCoversEveryModelInCurrentSchema`
        // fails the build the moment a schema model is missing from it.
        let bodyMetrics = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        let importedWorkouts = try context.fetch(FetchDescriptor<ImportedWorkout>())
        // Metadata only: the photo/video binaries under `ProgressMediaStore`
        // never enter the JSON (they would balloon a text backup by orders of
        // magnitude and JSON has no sane binary encoding). The export UI
        // already discloses that media files stay on the device.
        let progressMedia = try context.fetch(FetchDescriptor<ProgressMediaAttachment>())
        let customNotifications = try context.fetch(FetchDescriptor<CustomNotification>())

        let payload = Payload(
            formatVersion: currentVersion,
            exportedAt: resolvedNow,
            exercises: exercises.map(ExerciseRecord.init),
            sets: sets.map(SetRecord.init),
            supplementTypes: supplementTypes.map(SupplementTypeRecord.init),
            supplementEntries: supplementEntries.map(SupplementEntryRecord.init),
            sessions: sessions.map(SessionRecord.init),
            plans: plans.map(PlanRecord.init),
            sprintPrescriptions: sprintPrescriptions.map(SprintPrescriptionRecord.init),
            sprintGoalSnapshots: sprintGoalSnapshots.map(SprintGoalSnapshotRecord.init),
            bodyMetrics: bodyMetrics.map(BodyMetricRecord.init),
            importedWorkouts: importedWorkouts.map(ImportedWorkoutRecord.init),
            progressMedia: progressMedia.map(ProgressMediaRecord.init),
            customNotifications: customNotifications.map(CustomNotificationRecord.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return MarbleBackupDocument(data: try encoder.encode(payload))
    }

    static func inspect(data: Data) throws -> MarbleBackupSummary {
        let payload = try decode(data)
        return MarbleBackupSummary(
            exercises: payload.exercises.count,
            sets: payload.sets.count,
            supplementLogs: payload.supplementEntries.count,
            sessions: payload.sessions.count,
            plans: payload.plans.count,
            bodyMetrics: (payload.bodyMetrics ?? []).count,
            importedWorkouts: (payload.importedWorkouts ?? []).count,
            progressMedia: (payload.progressMedia ?? []).count,
            customNotifications: (payload.customNotifications ?? []).count
        )
    }

    @discardableResult
    static func restore(data: Data, into context: ModelContext) throws -> MarbleBackupSummary {
        let payload = try decode(data)
        try validate(payload)
        let now = AppEnvironment.now
        var insertedExercises = 0
        var insertedSets = 0
        var insertedSupplementEntries = 0
        var insertedSessions = 0
        var insertedPlans = 0
        var insertedBodyMetrics = 0
        var insertedImportedWorkouts = 0
        var insertedProgressMedia = 0
        var insertedCustomNotifications = 0

        var exercises = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0) })
        for record in payload.exercises where exercises[record.id] == nil {
            let exercise = Exercise(
                id: record.id,
                name: record.name,
                category: record.category,
                customIconEmoji: record.customIconEmoji,
                resistanceTrackingStyle: record.resistanceTrackingStyle,
                preferredDistanceUnit: record.preferredDistanceUnit,
                metrics: record.metrics,
                defaultRestSeconds: record.defaultRestSeconds,
                isFavorite: record.isFavorite,
                createdAt: record.createdAt
            )
            context.insert(exercise)
            exercises[record.id] = exercise
            insertedExercises += 1
        }

        let existingSprintExerciseIDs = Set(try context.fetch(FetchDescriptor<SprintPrescription>()).map(\.exerciseID))
        for record in payload.sprintPrescriptions ?? [] where !existingSprintExerciseIDs.contains(record.exerciseID) {
            guard exercises[record.exerciseID] != nil else { throw MarbleBackupError.missingExercise(record.exerciseID) }
            context.insert(SprintPrescription(
                id: record.id,
                exerciseID: record.exerciseID,
                distance: record.distance,
                repetitionCount: record.repetitionCount,
                targetLowerSeconds: record.targetLowerSeconds,
                targetUpperSeconds: record.targetUpperSeconds,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
        }

        var supplementTypes = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SupplementType>()).map { ($0.id, $0) })
        for record in payload.supplementTypes where supplementTypes[record.id] == nil {
            let type = SupplementType(
                id: record.id,
                name: record.name,
                defaultDose: record.defaultDose,
                unit: record.unit,
                isFavorite: record.isFavorite
            )
            context.insert(type)
            supplementTypes[record.id] = type
        }

        let existingSetIDs = Set(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id))
        var restoredSets: [UUID: SetEntry] = [:]
        for record in payload.sets {
            if existingSetIDs.contains(record.id) { continue }
            guard let exercise = exercises[record.exerciseID] else { throw MarbleBackupError.missingExercise(record.exerciseID) }
            let entry = SetEntry(
                id: record.id,
                exercise: exercise,
                performedAt: record.performedAt,
                weight: record.weight,
                weightUnit: record.weightUnit,
                reps: record.reps,
                distance: record.distance,
                distanceUnit: record.distanceUnit,
                durationSeconds: record.durationSeconds,
                difficulty: record.difficulty,
                restAfterSeconds: record.restAfterSeconds,
                notes: record.notes,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(entry)
            restoredSets[record.id] = entry
            insertedSets += 1
        }

        let allSets = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SetEntry>()).map { ($0.id, $0) })
            .merging(restoredSets) { _, restored in restored }

        let existingSprintGoalSetIDs = Set(try context.fetch(FetchDescriptor<SprintGoalSnapshot>()).map(\.setEntryID))
        for record in payload.sprintGoalSnapshots ?? [] where !existingSprintGoalSetIDs.contains(record.setEntryID) {
            guard allSets[record.setEntryID] != nil else { throw MarbleBackupError.invalidPayload }
            context.insert(SprintGoalSnapshot(
                id: record.id,
                setEntryID: record.setEntryID,
                exerciseID: record.exerciseID,
                distance: record.distance,
                distanceUnit: record.distanceUnit,
                repetitionNumber: record.repetitionNumber,
                repetitionCount: record.repetitionCount,
                targetLowerSeconds: record.targetLowerSeconds,
                targetUpperSeconds: record.targetUpperSeconds,
                isInferred: record.isInferred,
                createdAt: record.createdAt
            ))
        }

        let existingSessions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.id, $0) })
        for record in payload.sessions {
            let sessionEntries = record.entryIDs.compactMap { allSets[$0] }
            if let existingSession = existingSessions[record.id] {
                let existingEntryIDs = Set(existingSession.entries.map(\.id))
                let missingEntries = sessionEntries.filter { !existingEntryIDs.contains($0.id) }
                if !missingEntries.isEmpty {
                    existingSession.entries.append(contentsOf: missingEntries)
                    existingSession.updatedAt = max(existingSession.updatedAt, record.updatedAt)
                }
            } else {
                let session = WorkoutSession(
                    id: record.id,
                    title: record.title,
                    startedAt: record.startedAt,
                    endedAt: record.endedAt,
                    notes: record.notes,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    entries: sessionEntries
                )
                context.insert(session)
                insertedSessions += 1
            }
        }

        // The import ledger has TWO database-level unique constraints: `id` and
        // `deduplicationKey` ("<source>:<externalID>"). Dedup on both. The same
        // Garmin/Strava/Health workout imported independently on two phones gets
        // two different row UUIDs but the identical key, and inserting the
        // "new" id would make SwiftData *upsert* over the user's existing row
        // on the key collision (that is the constraint's documented behavior in
        // `ImportedWorkout`) instead of merging alongside it.
        let existingImports = try context.fetch(FetchDescriptor<ImportedWorkout>())
        let existingImportsByID = Dictionary(uniqueKeysWithValues: existingImports.map { ($0.id, $0) })
        let existingImportsByKey = Dictionary(uniqueKeysWithValues: existingImports.map { ($0.deduplicationKey, $0) })
        for record in payload.importedWorkouts ?? [] {
            if let existing = existingImportsByID[record.id] ?? existingImportsByKey[record.deduplicationKey] {
                // Same repair rule as sessions above: an existing ledger row
                // adopts restored entries it should own but doesn't. Entries
                // already claimed by another import are never stolen —
                // `SetEntry.importedWorkout` is to-one and the current owner
                // is the record of truth on this device.
                let linkedEntryIDs = Set(existing.entries.map(\.id))
                for entryID in record.entryIDs where !linkedEntryIDs.contains(entryID) {
                    if let entry = allSets[entryID], entry.importedWorkout == nil {
                        entry.importedWorkout = existing
                    }
                }
                continue
            }
            let imported = ImportedWorkout(
                id: record.id,
                source: ImportSource(rawValue: record.sourceRaw) ?? .appleHealth,
                externalID: record.externalID,
                title: record.title,
                workoutDate: record.workoutDate,
                setsImported: record.setsImported,
                importedAt: record.importedAt,
                originName: record.originName,
                sourceAppName: record.sourceAppName,
                deviceName: record.deviceName,
                distanceMeters: record.distanceMeters,
                durationSeconds: record.durationSeconds,
                calories: record.calories,
                averageHeartRate: record.averageHeartRate,
                maxHeartRate: record.maxHeartRate,
                elevationAscendedMeters: record.elevationAscendedMeters,
                isIndoor: record.isIndoor
            )
            // Raw strings pass through verbatim (see `ImportedWorkoutRecord`):
            // a source or activity kind this build doesn't know about must
            // survive the round trip, so the enum-typed init parameters are
            // bypassed for these. `validate` has already proven the key still
            // matches "<sourceRaw>:<externalID>".
            imported.sourceRaw = record.sourceRaw
            imported.deduplicationKey = record.deduplicationKey
            imported.kindRaw = record.kindRaw
            context.insert(imported)
            for entryID in record.entryIDs {
                if let entry = allSets[entryID], entry.importedWorkout == nil {
                    entry.importedWorkout = imported
                }
            }
            insertedImportedWorkouts += 1
        }

        let existingSupplementEntryIDs = Set(try context.fetch(FetchDescriptor<SupplementEntry>()).map(\.id))
        for record in payload.supplementEntries where !existingSupplementEntryIDs.contains(record.id) {
            guard let type = supplementTypes[record.typeID] else { throw MarbleBackupError.missingSupplementType(record.typeID) }
            context.insert(SupplementEntry(
                id: record.id,
                type: type,
                takenAt: record.takenAt,
                dose: record.dose,
                unit: record.unit,
                notes: record.notes,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
            insertedSupplementEntries += 1
        }

        let existingPlanIDs = Set(try context.fetch(FetchDescriptor<SplitPlan>()).map(\.id))
        for record in payload.plans where !existingPlanIDs.contains(record.id) {
            let plan = SplitPlan(
                id: record.id,
                name: record.name,
                isActive: record.isActive,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            plan.days = record.days.map { dayRecord in
                let day = SplitDay(
                    id: dayRecord.id,
                    weekday: dayRecord.weekday,
                    title: dayRecord.title,
                    notes: dayRecord.notes,
                    order: dayRecord.order,
                    createdAt: dayRecord.createdAt,
                    updatedAt: dayRecord.updatedAt,
                    plan: plan
                )
                day.plannedSets = dayRecord.plannedSets.compactMap { setRecord in
                    guard let exercise = exercises[setRecord.exerciseID] else { return nil }
                    return PlannedSet(
                        id: setRecord.id,
                        order: setRecord.order,
                        notes: setRecord.notes,
                        createdAt: setRecord.createdAt,
                        updatedAt: setRecord.updatedAt,
                        exercise: exercise,
                        day: day
                    )
                }
                return day
            }
            context.insert(plan)
            insertedPlans += 1
        }

        // Standalone by design — no relationship to resolve, so this only needs
        // the same id-based dedup as `existingSetIDs`. `id` is
        // `@Attribute(.unique)`, so skipping the check would upsert over a row
        // the user already has rather than merging alongside it.
        let existingBodyMetricIDs = Set(try context.fetch(FetchDescriptor<BodyMetricEntry>()).map(\.id))
        for record in payload.bodyMetrics ?? [] where !existingBodyMetricIDs.contains(record.id) {
            context.insert(BodyMetricEntry(
                id: record.id,
                measuredAt: record.measuredAt,
                weightKilograms: record.weightKilograms,
                bodyFatPercent: record.bodyFatPercent,
                source: record.source,
                healthKitUUID: record.healthKitUUID,
                notes: record.notes,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
            insertedBodyMetrics += 1
        }

        // Metadata only, like the export side: the row's filenames point into
        // `ProgressMediaStore`'s on-disk directory, and the binaries themselves
        // are NOT in the JSON backup. On a fresh device the restored row's
        // media will be missing until the store's files arrive by other means
        // (a full device transfer); every `ProgressMediaStore` load resolves a
        // missing file to nil and the calendar's media section falls back to
        // its placeholder state, so restoring the row loses nothing and
        // preserves the date/kind/crop the user set up.
        let existingProgressMediaIDs = Set(try context.fetch(FetchDescriptor<ProgressMediaAttachment>()).map(\.id))
        for record in payload.progressMedia ?? [] where !existingProgressMediaIDs.contains(record.id) {
            let attachment = ProgressMediaAttachment(
                id: record.id,
                attachedToDate: record.attachedToDate,
                kind: ProgressMediaKind(rawValue: record.kindRaw) ?? .photo,
                originalFilename: record.originalFilename,
                thumbnailFilename: record.thumbnailFilename,
                fileSizeBytes: record.fileSizeBytes,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            // Raw string passes through verbatim for the same forward-compat
            // reason as `ImportedWorkout.sourceRaw`, and the crop components
            // are set individually so a partially-present crop (a hand-edited
            // file) round-trips exactly as stored instead of collapsing to nil.
            attachment.kindRaw = record.kindRaw
            attachment.photoCropX = record.photoCropX
            attachment.photoCropY = record.photoCropY
            attachment.photoCropWidth = record.photoCropWidth
            attachment.photoCropHeight = record.photoCropHeight
            context.insert(attachment)
            insertedProgressMedia += 1
        }

        // Persistence only: inserting the row does not tell
        // UNUserNotificationCenter anything. The restore call site is
        // responsible for re-syncing schedules afterwards (see
        // `DataManagementView.rescheduleRestoredNotifications`) — keeping the
        // notification-center dependency out of this service is what lets the
        // whole restore path run in unit tests. The 10-notification cap is a
        // creation-time UI rule; a restore never drops rows to enforce it,
        // because silently dropping data is the bug class this file fights.
        let existingNotificationIDs = Set(try context.fetch(FetchDescriptor<CustomNotification>()).map(\.id))
        for record in payload.customNotifications ?? [] where !existingNotificationIDs.contains(record.id) {
            context.insert(CustomNotification(
                id: record.id,
                message: record.message,
                hour: record.hour,
                minute: record.minute,
                weekdayMask: record.weekdayMask,
                isEnabled: record.isEnabled,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
            insertedCustomNotifications += 1
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        UserDefaults.standard.set(now, forKey: PersistenceRecoveryNotice.lastSuccessfulRestoreKey)
        return MarbleBackupSummary(
            exercises: insertedExercises,
            sets: insertedSets,
            supplementLogs: insertedSupplementEntries,
            sessions: insertedSessions,
            plans: insertedPlans,
            bodyMetrics: insertedBodyMetrics,
            importedWorkouts: insertedImportedWorkouts,
            progressMedia: insertedProgressMedia,
            customNotifications: insertedCustomNotifications
        )
    }

    private static func decode(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            throw MarbleBackupError.invalidPayload
        }
        guard payload.formatVersion == currentVersion else {
            throw MarbleBackupError.unsupportedVersion(payload.formatVersion)
        }
        return payload
    }

    private static func validate(_ payload: Payload) throws {
        func hasUniqueIDs<T>(_ values: [T], id: (T) -> UUID) -> Bool {
            Set(values.map(id)).count == values.count
        }

        guard hasUniqueIDs(payload.exercises, id: \.id),
              hasUniqueIDs(payload.sets, id: \.id),
              hasUniqueIDs(payload.supplementTypes, id: \.id),
              hasUniqueIDs(payload.supplementEntries, id: \.id),
              hasUniqueIDs(payload.sessions, id: \.id),
              hasUniqueIDs(payload.plans, id: \.id),
              hasUniqueIDs(payload.sprintPrescriptions ?? [], id: \.id),
              hasUniqueIDs(payload.sprintGoalSnapshots ?? [], id: \.id),
              hasUniqueIDs(payload.bodyMetrics ?? [], id: \.id),
              hasUniqueIDs(payload.importedWorkouts ?? [], id: \.id),
              hasUniqueIDs(payload.progressMedia ?? [], id: \.id),
              hasUniqueIDs(payload.customNotifications ?? [], id: \.id)
        else {
            throw MarbleBackupError.invalidPayload
        }

        // Deliberately narrow. A NaN or non-positive bodyweight would poison
        // the Trends chart and divide DOTS by zero, so it is rejected before
        // anything is written; body fat is only checked for finiteness, never
        // for a plausible range — refusing an entire restore over one odd
        // Health sample would be the data loss this fix exists to prevent.
        guard (payload.bodyMetrics ?? []).allSatisfy({ metric in
            metric.weightKilograms.isFinite
                && metric.weightKilograms > 0
                && metric.bodyFatPercent.map(\.isFinite) != false
        }) else {
            throw MarbleBackupError.invalidPayload
        }

        let exerciseIDs = Set(payload.exercises.map(\.id))
        let setIDs = Set(payload.sets.map(\.id))
        let exerciseIDBySetID = Dictionary(uniqueKeysWithValues: payload.sets.map { ($0.id, $0.exerciseID) })
        let supplementTypeIDs = Set(payload.supplementTypes.map(\.id))
        let days = payload.plans.flatMap(\.days)
        let plannedSets = days.flatMap(\.plannedSets)
        let sprintPrescriptions = payload.sprintPrescriptions ?? []
        let sprintGoalSnapshots = payload.sprintGoalSnapshots ?? []
        let importedWorkouts = payload.importedWorkouts ?? []
        let importedEntryIDs = importedWorkouts.flatMap(\.entryIDs)

        guard hasUniqueIDs(days, id: \.id),
              hasUniqueIDs(plannedSets, id: \.id),
              payload.sets.allSatisfy({ exerciseIDs.contains($0.exerciseID) }),
              payload.supplementEntries.allSatisfy({ supplementTypeIDs.contains($0.typeID) }),
              payload.sessions.allSatisfy({ session in session.entryIDs.allSatisfy(setIDs.contains) }),
              plannedSets.allSatisfy({ exerciseIDs.contains($0.exerciseID) }),
              sprintPrescriptions.allSatisfy({ exerciseIDs.contains($0.exerciseID) }),
              Set(sprintPrescriptions.map(\.exerciseID)).count == sprintPrescriptions.count,
              sprintPrescriptions.allSatisfy({
                  SprintPrescriptionPlan(
                      distance: $0.distance,
                      repetitionCount: $0.repetitionCount,
                      targetLowerSeconds: $0.targetLowerSeconds,
                      targetUpperSeconds: $0.targetUpperSeconds
                  ).isValid
              }),
              sprintGoalSnapshots.allSatisfy({ snapshot in
                  setIDs.contains(snapshot.setEntryID) &&
                  exerciseIDs.contains(snapshot.exerciseID) &&
                  exerciseIDBySetID[snapshot.setEntryID] == snapshot.exerciseID
              }),
              Set(sprintGoalSnapshots.map(\.setEntryID)).count == sprintGoalSnapshots.count,
              sprintGoalSnapshots.allSatisfy({ snapshot in
                  SprintPrescriptionPlan(
                      distance: snapshot.distance,
                      repetitionCount: snapshot.repetitionCount,
                      targetLowerSeconds: snapshot.targetLowerSeconds,
                      targetUpperSeconds: snapshot.targetUpperSeconds
                  ).isValid && snapshot.repetitionNumber.map {
                      (1...snapshot.repetitionCount).contains($0)
                  } != false
              }),
              // Import-ledger integrity, all proven before anything is
              // written. `deduplicationKey` carries a `.unique` constraint, so
              // two records sharing one key could never coexist after restore;
              // the format check pins the "<source>:<externalID>" derivation
              // the model documents, because a mismatched key would make the
              // dedup-on-restore and the database constraint disagree about
              // which rows are "the same" workout. Entry references get the
              // same treatment as session `entryIDs`, plus a no-sharing check:
              // `SetEntry.importedWorkout` is to-one, so an entry claimed by
              // two ledger rows is structurally impossible to restore.
              importedWorkouts.allSatisfy({ record in
                  record.deduplicationKey == "\(record.sourceRaw):\(record.externalID)"
                      && record.entryIDs.allSatisfy(setIDs.contains)
              }),
              Set(importedWorkouts.map(\.deduplicationKey)).count == importedWorkouts.count,
              Set(importedEntryIDs).count == importedEntryIDs.count
        else {
            throw MarbleBackupError.invalidPayload
        }
        // Deliberately nothing for `progressMedia` and `customNotifications`
        // beyond the unique-id checks above. Both are standalone rows with no
        // references to verify, and an odd value is harmless downstream — an
        // unknown media kind falls back to `.photo`, and the scheduler already
        // refuses to schedule anything failing `isValidSchedule`. Rejecting an
        // entire restore over one odd row would be the data loss this
        // validation exists to prevent (same reasoning as body fat above).
    }
}

private nonisolated struct Payload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let exercises: [ExerciseRecord]
    let sets: [SetRecord]
    let supplementTypes: [SupplementTypeRecord]
    let supplementEntries: [SupplementEntryRecord]
    let sessions: [SessionRecord]
    let plans: [PlanRecord]
    let sprintPrescriptions: [SprintPrescriptionRecord]?
    let sprintGoalSnapshots: [SprintGoalSnapshotRecord]?
    /// Optional for the same reason as the two above: a 2.1-era backup has no
    /// such key, and it must still restore. That is what lets `formatVersion`
    /// stay at 1 instead of orphaning every existing backup file.
    let bodyMetrics: [BodyMetricRecord]?
    /// The import dedup ledger. Optional like every post-1.0 array — its
    /// absence in older files must never fail a restore. Losing it is what
    /// made every re-import after a restore create duplicate journal entries.
    let importedWorkouts: [ImportedWorkoutRecord]?
    /// Progress photo/video METADATA only — the media binaries live on disk
    /// under `ProgressMediaStore` and are deliberately not in the JSON backup.
    /// See `ProgressMediaRecord` for the full rationale.
    let progressMedia: [ProgressMediaRecord]?
    let customNotifications: [CustomNotificationRecord]?
}

private nonisolated struct ImportedWorkoutRecord: Codable {
    let id: UUID
    /// Raw strings, not `ImportSource`/`ImportedActivityKind`: the model
    /// itself stores `sourceRaw`/`kindRaw` so rows survive builds that don't
    /// know a value, and the backup must be at least as tolerant as the model
    /// — decoding a typed enum would fail the *entire* restore on the first
    /// unknown case in the file.
    let sourceRaw: String
    let externalID: String
    /// Mirrors the `.unique` database constraint, always
    /// "<sourceRaw>:<externalID>". Stored explicitly rather than re-derived so
    /// `validate` can prove the file is internally consistent before restore
    /// touches the store.
    let deduplicationKey: String
    let title: String
    let workoutDate: Date
    let setsImported: Int
    let importedAt: Date
    let kindRaw: String?
    let originName: String?
    let sourceAppName: String?
    let deviceName: String?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let calories: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let elevationAscendedMeters: Double?
    let isIndoor: Bool?
    /// Same ID-reference style as `SessionRecord.entryIDs`. The relationship
    /// lives on this side of the file because `SetRecord` predates
    /// `SetEntry.importedWorkout` — adding a key to the older record would be
    /// a wire-format change, while a self-contained list here is purely
    /// additive. Restore rebuilds `SetEntry.importedWorkout` from it.
    let entryIDs: [UUID]

    @MainActor init(_ workout: ImportedWorkout) {
        id = workout.id
        sourceRaw = workout.sourceRaw
        externalID = workout.externalID
        deduplicationKey = workout.deduplicationKey
        title = workout.title
        workoutDate = workout.workoutDate
        setsImported = workout.setsImported
        importedAt = workout.importedAt
        kindRaw = workout.kindRaw
        originName = workout.originName
        sourceAppName = workout.sourceAppName
        deviceName = workout.deviceName
        distanceMeters = workout.distanceMeters
        durationSeconds = workout.durationSeconds
        calories = workout.calories
        averageHeartRate = workout.averageHeartRate
        maxHeartRate = workout.maxHeartRate
        elevationAscendedMeters = workout.elevationAscendedMeters
        isIndoor = workout.isIndoor
        entryIDs = workout.entries.map(\.id)
    }
}

/// Metadata for one progress photo/video. **The media binary is NOT in the
/// JSON backup** — `originalFilename`/`thumbnailFilename` are references into
/// `ProgressMediaStore`'s on-disk directory, which never enters this file.
/// Embedding megabytes of image/video data in a pretty-printed JSON document
/// is a non-starter, and the Data & Backups screen already tells the user
/// "Progress photos and videos stay on this device." Backing up the row keeps
/// the attachment's date, kind, crop, and file identity so nothing structural
/// is lost — the binaries travel only via a full device transfer.
private nonisolated struct ProgressMediaRecord: Codable {
    let id: UUID
    let attachedToDate: Date
    /// Raw string for the same forward-compat reason as
    /// `ImportedWorkoutRecord.sourceRaw`.
    let kindRaw: String
    let originalFilename: String
    let thumbnailFilename: String?
    let photoCropX: Double?
    let photoCropY: Double?
    let photoCropWidth: Double?
    let photoCropHeight: Double?
    let fileSizeBytes: Int64?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ attachment: ProgressMediaAttachment) {
        id = attachment.id
        attachedToDate = attachment.attachedToDate
        kindRaw = attachment.kindRaw
        originalFilename = attachment.originalFilename
        thumbnailFilename = attachment.thumbnailFilename
        photoCropX = attachment.photoCropX
        photoCropY = attachment.photoCropY
        photoCropWidth = attachment.photoCropWidth
        photoCropHeight = attachment.photoCropHeight
        fileSizeBytes = attachment.fileSizeBytes
        createdAt = attachment.createdAt
        updatedAt = attachment.updatedAt
    }
}

private nonisolated struct CustomNotificationRecord: Codable {
    let id: UUID
    let message: String
    let hour: Int
    let minute: Int
    /// The weekday bitmask exactly as stored (bit N-1 = `Weekday` rawValue N,
    /// see `Weekday.notificationBitMask`) — no expansion into day names on the
    /// way through the file.
    let weekdayMask: Int
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ notification: CustomNotification) {
        id = notification.id
        message = notification.message
        hour = notification.hour
        minute = notification.minute
        weekdayMask = notification.weekdayMask
        isEnabled = notification.isEnabled
        createdAt = notification.createdAt
        updatedAt = notification.updatedAt
    }
}

private nonisolated struct BodyMetricRecord: Codable {
    let id: UUID
    let measuredAt: Date
    /// Canonical kilograms, exactly as stored — no unit lives beside it and
    /// nothing converts on the way through the file. See `BodyMetricEntry`.
    let weightKilograms: Double
    let bodyFatPercent: Double?
    let source: BodyMetricSource
    let healthKitUUID: UUID?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ entry: BodyMetricEntry) {
        id = entry.id
        measuredAt = entry.measuredAt
        weightKilograms = entry.weightKilograms
        bodyFatPercent = entry.bodyFatPercent
        source = entry.source
        healthKitUUID = entry.healthKitUUID
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }
}

private nonisolated struct SprintGoalSnapshotRecord: Codable {
    let id: UUID
    let setEntryID: UUID
    let exerciseID: UUID
    let distance: Double
    let distanceUnit: DistanceUnit
    let repetitionNumber: Int?
    let repetitionCount: Int
    let targetLowerSeconds: Int
    let targetUpperSeconds: Int
    let isInferred: Bool
    let createdAt: Date

    @MainActor init(_ snapshot: SprintGoalSnapshot) {
        id = snapshot.id
        setEntryID = snapshot.setEntryID
        exerciseID = snapshot.exerciseID
        distance = snapshot.distance
        distanceUnit = snapshot.distanceUnit
        repetitionNumber = snapshot.repetitionNumber
        repetitionCount = snapshot.repetitionCount
        targetLowerSeconds = snapshot.targetLowerSeconds
        targetUpperSeconds = snapshot.targetUpperSeconds
        isInferred = snapshot.isInferred
        createdAt = snapshot.createdAt
    }
}

private nonisolated struct SprintPrescriptionRecord: Codable {
    let id: UUID
    let exerciseID: UUID
    let distance: Double
    let repetitionCount: Int
    let targetLowerSeconds: Int
    let targetUpperSeconds: Int
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ prescription: SprintPrescription) {
        id = prescription.id
        exerciseID = prescription.exerciseID
        distance = prescription.distance
        repetitionCount = prescription.repetitionCount
        targetLowerSeconds = prescription.targetLowerSeconds
        targetUpperSeconds = prescription.targetUpperSeconds
        createdAt = prescription.createdAt
        updatedAt = prescription.updatedAt
    }
}

private nonisolated struct ExerciseRecord: Codable {
    let id: UUID
    let name: String
    let category: ExerciseCategory
    let customIconEmoji: String?
    let resistanceTrackingStyle: ResistanceTrackingStyle
    let preferredDistanceUnit: DistanceUnit
    let metrics: ExerciseMetricsProfile
    let defaultRestSeconds: Int
    let isFavorite: Bool
    let createdAt: Date

    @MainActor init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        category = exercise.category
        customIconEmoji = exercise.customIconEmoji
        resistanceTrackingStyle = exercise.resistanceTrackingStyle
        preferredDistanceUnit = exercise.preferredDistanceUnit
        metrics = exercise.metrics
        defaultRestSeconds = exercise.defaultRestSeconds
        isFavorite = exercise.isFavorite
        createdAt = exercise.createdAt
    }
}

private nonisolated struct SetRecord: Codable {
    let id: UUID
    let exerciseID: UUID
    let performedAt: Date
    let weight: Double?
    let weightUnit: WeightUnit
    let reps: Int?
    let distance: Double?
    let distanceUnit: DistanceUnit
    let durationSeconds: Int?
    let difficulty: Int
    let restAfterSeconds: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ entry: SetEntry) {
        id = entry.id
        exerciseID = entry.exercise.id
        performedAt = entry.performedAt
        weight = entry.weight
        weightUnit = entry.weightUnit
        reps = entry.reps
        distance = entry.distance
        distanceUnit = entry.distanceUnit
        durationSeconds = entry.durationSeconds
        difficulty = entry.difficulty
        restAfterSeconds = entry.restAfterSeconds
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }
}

private nonisolated struct SupplementTypeRecord: Codable {
    let id: UUID
    let name: String
    let defaultDose: Double?
    let unit: SupplementUnit
    let isFavorite: Bool

    @MainActor init(_ type: SupplementType) {
        id = type.id
        name = type.name
        defaultDose = type.defaultDose
        unit = type.unit
        isFavorite = type.isFavorite
    }
}

private nonisolated struct SupplementEntryRecord: Codable {
    let id: UUID
    let typeID: UUID
    let takenAt: Date
    let dose: Double?
    let unit: SupplementUnit
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ entry: SupplementEntry) {
        id = entry.id
        typeID = entry.type.id
        takenAt = entry.takenAt
        dose = entry.dose
        unit = entry.unit
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }
}

private nonisolated struct SessionRecord: Codable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let entryIDs: [UUID]

    @MainActor init(_ session: WorkoutSession) {
        id = session.id
        title = session.title
        startedAt = session.startedAt
        endedAt = session.endedAt
        notes = session.notes
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        entryIDs = session.entries.map(\.id)
    }
}

private nonisolated struct PlanRecord: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let days: [DayRecord]

    @MainActor init(_ plan: SplitPlan) {
        id = plan.id
        name = plan.name
        isActive = plan.isActive
        createdAt = plan.createdAt
        updatedAt = plan.updatedAt
        days = plan.days.map(DayRecord.init)
    }
}

private nonisolated struct DayRecord: Codable {
    let id: UUID
    let weekday: Weekday
    let title: String
    let notes: String?
    let order: Int
    let createdAt: Date
    let updatedAt: Date
    let plannedSets: [PlannedSetRecord]

    @MainActor init(_ day: SplitDay) {
        id = day.id
        weekday = day.weekday
        title = day.title
        notes = day.notes
        order = day.order
        createdAt = day.createdAt
        updatedAt = day.updatedAt
        plannedSets = day.plannedSets.map(PlannedSetRecord.init)
    }
}

private nonisolated struct PlannedSetRecord: Codable {
    let id: UUID
    let order: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let exerciseID: UUID

    @MainActor init(_ plannedSet: PlannedSet) {
        id = plannedSet.id
        order = plannedSet.order
        notes = plannedSet.notes
        createdAt = plannedSet.createdAt
        updatedAt = plannedSet.updatedAt
        exerciseID = plannedSet.exercise.id
    }
}

enum PersistenceRecoveryNotice {
    static let recoveryDateKey = "persistenceRecoveryDate"
    static let recoveryBackupNameKey = "persistenceRecoveryBackupName"
    static let acknowledgedKey = "persistenceRecoveryAcknowledged"
    static let lastSuccessfulRestoreKey = "persistenceLastSuccessfulRestore"

    static var needsAttention: Bool {
        UserDefaults.standard.object(forKey: recoveryDateKey) != nil
            && !UserDefaults.standard.bool(forKey: acknowledgedKey)
    }

    static func record(backupName: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: recoveryDateKey)
        UserDefaults.standard.set(backupName, forKey: recoveryBackupNameKey)
        UserDefaults.standard.set(false, forKey: acknowledgedKey)
    }

    static func acknowledge() {
        UserDefaults.standard.set(true, forKey: acknowledgedKey)
    }
}
