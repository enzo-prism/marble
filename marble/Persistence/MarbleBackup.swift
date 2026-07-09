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

        let payload = Payload(
            formatVersion: currentVersion,
            exportedAt: resolvedNow,
            exercises: exercises.map(ExerciseRecord.init),
            sets: sets.map(SetRecord.init),
            supplementTypes: supplementTypes.map(SupplementTypeRecord.init),
            supplementEntries: supplementEntries.map(SupplementEntryRecord.init),
            sessions: sessions.map(SessionRecord.init),
            plans: plans.map(PlanRecord.init)
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
            plans: payload.plans.count
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
            plans: insertedPlans
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
              hasUniqueIDs(payload.plans, id: \.id)
        else {
            throw MarbleBackupError.invalidPayload
        }

        let exerciseIDs = Set(payload.exercises.map(\.id))
        let setIDs = Set(payload.sets.map(\.id))
        let supplementTypeIDs = Set(payload.supplementTypes.map(\.id))
        let days = payload.plans.flatMap(\.days)
        let plannedSets = days.flatMap(\.plannedSets)

        guard hasUniqueIDs(days, id: \.id),
              hasUniqueIDs(plannedSets, id: \.id),
              payload.sets.allSatisfy({ exerciseIDs.contains($0.exerciseID) }),
              payload.supplementEntries.allSatisfy({ supplementTypeIDs.contains($0.typeID) }),
              payload.sessions.allSatisfy({ session in session.entryIDs.allSatisfy(setIDs.contains) }),
              plannedSets.allSatisfy({ exerciseIDs.contains($0.exerciseID) })
        else {
            throw MarbleBackupError.invalidPayload
        }
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
