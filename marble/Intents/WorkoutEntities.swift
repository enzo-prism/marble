import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated enum DistanceUnitAppEnum: String, AppEnum, CaseIterable {
    case meters, yards, feet, kilometers, miles
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Distance Unit" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.meters: "Meters", .yards: "Yards", .feet: "Feet", .kilometers: "Kilometers", .miles: "Miles"]
    }
    var unit: DistanceUnit { DistanceUnit(rawValue: rawValue)! }
}

/// Stable identity for a confirmed set, so follow-up actions never guess from a timestamp.
nonisolated struct LoggedSetEntity: AppEntity, Transferable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Logged Set" }
    static var defaultQuery: LoggedSetQuery { LoggedSetQuery() }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    let id: UUID
    @Property(title: "Exercise") nonisolated(unsafe) var exerciseName: String
    @Property(title: "Performed At") nonisolated(unsafe) var performedAt: Date
    @Property(title: "Summary") nonisolated(unsafe) var summary: String
    @Property(title: "Reps") nonisolated(unsafe) var reps: Int?
    @Property(title: "Weight") nonisolated(unsafe) var weight: Double?
    @Property(title: "Weight Unit") nonisolated(unsafe) var weightUnit: WeightUnitAppEnum?
    @Property(title: "Distance") nonisolated(unsafe) var distance: Double?
    @Property(title: "Distance Unit") nonisolated(unsafe) var distanceUnit: DistanceUnitAppEnum?
    @Property(title: "Duration in Seconds") nonisolated(unsafe) var durationSeconds: Double?
    var displayRepresentation: DisplayRepresentation { .init(title: "\(exerciseName)", subtitle: "\(summary)") }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.summary.utf8) }
    }

    @MainActor
    init(_ entry: SetEntry) {
        let entryID = entry.id
        let detail = try? entry.modelContext?.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == entryID })).first
        self.init(entry, durationTenths: detail?.durationTenths)
    }

    @MainActor
    init(_ entry: SetEntry, durationTenths: Int?) {
        id = entry.id
        exerciseName = entry.exercise.name
        performedAt = entry.performedAt
        reps = entry.reps
        weight = entry.exercise.displayedWeightInput(from: entry.weight)
        weightUnit = entry.weight == nil ? nil : WeightUnitAppEnum(entry.weightUnit)
        distance = entry.distance
        distanceUnit = entry.distance == nil ? nil : DistanceUnitAppEnum(rawValue: entry.distanceUnit.rawValue)
        durationSeconds = durationTenths.map { Double($0) / 10 } ?? entry.durationSeconds.map(Double.init)
        summary = WorkoutCommands.summary(
            exercise: entry.exercise, metrics: entry.exercise.metrics,
            storedWeight: entry.weight, unit: entry.weightUnit, reps: entry.reps,
            distance: entry.distance, distanceUnit: entry.distanceUnit,
            durationSeconds: entry.durationSeconds, beatsExisting: [], earned: [],
            durationTenths: durationTenths
        )
    }
}

nonisolated struct LoggedSetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [LoggedSetEntity] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let entries = try context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { identifiers.contains($0.id) }))
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(LoggedSetEntity.init) }
    }
}

nonisolated struct WorkoutSessionEntity: AppEntity, IndexedEntity, Transferable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Workout" }
    static var defaultQuery: WorkoutSessionEntityQuery { WorkoutSessionEntityQuery() }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    let id: UUID
    @Property(title: "Title") nonisolated(unsafe) var title: String
    @Property(title: "Started At") nonisolated(unsafe) var startedAt: Date
    @Property(title: "Finished At") nonisolated(unsafe) var endedAt: Date?
    @Property(title: "Set Count") nonisolated(unsafe) var setCount: Int
    @Property(title: "Exercises") nonisolated(unsafe) var exercises: [String]
    @Property(title: "Summary") nonisolated(unsafe) var summary: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(setCount) sets · \(startedAt.formatted(date: .abbreviated, time: .omitted))") }
    var attributeSet: CSSearchableItemAttributeSet {
        let result = CSSearchableItemAttributeSet(contentType: .text)
        result.title = title
        result.contentDescription = "\(exercises.joined(separator: ", ")) · \(setCount) sets"
        result.startDate = startedAt
        return result
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.summary.utf8) }
    }
    @MainActor
    init(_ session: WorkoutSession) {
        id = session.id
        title = session.title
        startedAt = session.startedAt
        endedAt = session.endedAt
        setCount = session.entries.count
        var seen = Set<UUID>()
        exercises = session.orderedEntries.filter { seen.insert($0.exercise.id).inserted }.map { $0.exercise.name }
        let ids = session.entries.map(\.id)
        let details = (try? session.modelContext?.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { ids.contains($0.setEntryID) }))) ?? []
        let timings = Dictionary(details.map { ($0.setEntryID, $0.durationTenths) }, uniquingKeysWith: { first, _ in first })
        summary = (["\(session.title) — \(session.startedAt.formatted(date: .abbreviated, time: .shortened))", "\(setCount) sets"] + session.orderedEntries.map { LoggedSetEntity($0, durationTenths: timings[$0.id]).summary }).joined(separator: "\n")
    }
}

nonisolated struct WorkoutSessionEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WorkoutSessionEntity] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { identifiers.contains($0.id) }))
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(WorkoutSessionEntity.init) }
    }
    @MainActor
    func entities(matching string: String) async throws -> [WorkoutSessionEntity] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        return try context.fetch(WorkoutHistoryQuery.descriptor(search: string, day: nil)).prefix(20).map(WorkoutSessionEntity.init)
    }
    @MainActor
    func suggestedEntities() async throws -> [WorkoutSessionEntity] {
        try await entities(matching: "")
    }
}

struct OpenWorkoutSessionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Workout"
    static let description = IntentDescription("Opens the exact workout in Marble's history.")
    @Parameter(title: "Workout") var target: WorkoutSessionEntity
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(MarbleURLs.url("session/\(target.id.uuidString)")))
    }
}

struct OpenExerciseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Exercise"
    static let description = IntentDescription("Opens this exercise's progress and history in Marble.")
    @Parameter(title: "Exercise") var target: ExerciseEntity
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(MarbleURLs.url("exercise/\(target.id.uuidString)")))
    }
}

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct FindWorkoutsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Workouts"
    static let description = IntentDescription("Finds completed Marble workouts by title and optional day. Returns actual logged sessions without changing them.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Search", description: "Words in the workout title. Leave empty for recent workouts.") var search: String?
    @Parameter(title: "Date", description: "The day of the workout, when specified.") var date: Date?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[WorkoutSessionEntity]> {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let sessions = try context.fetch(WorkoutHistoryQuery.descriptor(search: search ?? "", day: date))
        return .result(value: Array(sessions.prefix(20)).map(WorkoutSessionEntity.init))
    }
}

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct ReviewRepeatedWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Repeated Workout"
    static let description = IntentDescription("Opens an editable copy of a completed workout for today. Nothing is saved until reviewed in Marble.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]
    @Parameter(title: "Workout", description: "The completed workout to copy for review.") var workout: WorkoutSessionEntity
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(MarbleURLs.url("repeat/\(workout.id.uuidString)")))
    }
}

@MainActor
enum WorkoutSessionSpotlightIndex {
    private static let identifiersKey = "marble.spotlight.workoutIDs"
    private static var operation: Task<Void, Never>?
    private static var generation = 0

    static func refresh() async {
        guard !TestHooks.isUITesting, !TestHooks.isXCTestProcess,
              let context = AppIntentsSupport.container?.mainContext else { return }
        let sessions = (try? context.fetch(WorkoutHistoryQuery.descriptor(search: "", day: nil))) ?? []
        let entities = sessions.prefix(50).map(WorkoutSessionEntity.init)
        generation += 1
        let expected = generation
        let previous = operation
        let next = Task {
            await previous?.value
            guard expected == generation else { return }
            let oldIDs = UserDefaults.standard.stringArray(forKey: identifiersKey)?.compactMap(UUID.init(uuidString:))
            if await index(entities, previousIDs: oldIDs) {
                UserDefaults.standard.set(entities.map { $0.id.uuidString }, forKey: identifiersKey)
            }
        }
        operation = next
        await next.value
    }

    static func removeAll() async {
        generation += 1
        await operation?.value
        if await index([], previousIDs: nil) { UserDefaults.standard.removeObject(forKey: identifiersKey) }
    }

    private nonisolated static func index(_ entities: [WorkoutSessionEntity], previousIDs: [UUID]?) async -> Bool {
        let index = CSSearchableIndex(name: "WorkoutSessions")
        do {
            if let previousIDs {
                let current = Set(entities.map(\.id))
                let stale = previousIDs.filter { !current.contains($0) }
                if !stale.isEmpty { try await index.deleteAppEntities(identifiedBy: stale, ofType: WorkoutSessionEntity.self) }
            } else {
                // First run also removes entries left by earlier versions without bookkeeping.
                try await index.deleteAppEntities(ofType: WorkoutSessionEntity.self)
            }
            if !entities.isEmpty { try await index.indexAppEntities(entities) }
            return true
        } catch { return false }
    }
}

nonisolated struct WorkoutIntentFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
