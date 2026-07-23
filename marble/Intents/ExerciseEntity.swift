import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

// MARK: - Entity

/// One exercise from the library, exposed to Siri, Shortcuts and Spotlight.
///
/// Deliberately a **value snapshot** rather than a wrapper around the SwiftData
/// `Exercise`: App Intents hands entities across process and isolation boundaries,
/// and a `nonisolated` struct of plain values sidesteps the whole class of problems
/// the target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting creates for
/// nonisolated protocol requirements (same reasoning as `ExerciseMetricsProfile`).
///
/// The category is flattened to its display string at construction time for the same
/// reason — `ExerciseCategory` is main-actor isolated because `symbolName` touches
/// `UIImage`, so an entity holding one could not be read from a nonisolated context.
nonisolated struct ExerciseEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Exercise" }
    static var defaultQuery: ExerciseQuery { ExerciseQuery() }

    /// Matches `Exercise.id` exactly, so the entity survives round-trips through
    /// saved Shortcuts and the Spotlight index.
    let id: UUID
    let name: String
    let categoryName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(categoryName)")
    }
}

extension ExerciseEntity {
    /// Main-actor because reading a SwiftData model is a main-actor operation here;
    /// everything it copies out is a plain value.
    @MainActor
    init(_ exercise: Exercise) {
        self.init(
            id: exercise.id,
            name: exercise.name,
            categoryName: exercise.category.displayName
        )
    }
}

// MARK: - Query

/// Resolves `ExerciseEntity` values for Siri, the Shortcuts editor and Spotlight.
///
/// Every fetch goes through `AppIntentsSupport.resolvedContainer()`'s `mainContext`,
/// matching `LogLastSetAgainIntent` — intents can run while the app was launched in
/// the background, and that helper is the one place that knows whether to reuse the
/// app's live container or build the in-memory test one.
nonisolated struct ExerciseQuery: EntityStringQuery {
    /// Siri reads suggestions aloud, so the list has to stay short enough to hear.
    static let suggestionLimit = 12

    init() {}

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ExerciseEntity] {
        let byID = Dictionary(
            Self.allExercises().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Preserve the caller's order — Shortcuts renders these in the order it asked.
        return identifiers.compactMap { byID[$0] }.map(ExerciseEntity.init)
    }

    /// Case- and diacritic-insensitive "name contains" match.
    ///
    /// Filtered in Swift rather than through a `#Predicate`: the exercise library is
    /// user-scale (tens of rows), and `localizedStandardContains` inside a SwiftData
    /// predicate has been an unreliable translation. Doing it here also makes the
    /// matching deterministic under test.
    @MainActor
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        let matches = Self.allExercises().filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        // Prefix matches first ("bench" → "Bench Press" before "Close-Grip Bench"),
        // then alphabetical so the list is stable across launches.
        return matches
            .sorted { lhs, rhs in
                let lhsPrefix = Self.hasPrefix(lhs.name, needle)
                let rhsPrefix = Self.hasPrefix(rhs.name, needle)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(ExerciseEntity.init)
    }

    /// Favorites first, then everything else — each group ordered by the exercise's
    /// most recent `SetEntry.performedAt` (never-logged exercises sort last within
    /// their group, then alphabetically so the order is stable).
    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        let context = AppIntentsSupport.resolvedContainer().mainContext
        let exercises = Self.allExercises()
        let lastPerformed = Self.lastPerformedDates(in: context)

        let ranked = exercises.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }

            let lhsDate = lastPerformed[lhs.id]
            let rhsDate = lastPerformed[rhs.id]
            switch (lhsDate, rhsDate) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            if lhs.name != rhs.name {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return ranked.prefix(Self.suggestionLimit).map(ExerciseEntity.init)
    }

    // MARK: - Fetch helpers

    @MainActor
    private static func allExercises() -> [Exercise] {
        let context = AppIntentsSupport.resolvedContainer().mainContext
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Newest `performedAt` per exercise, in one pass over a descending fetch.
    @MainActor
    private static func lastPerformedDates(in context: ModelContext) -> [UUID: Date] {
        let descriptor = FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        guard let entries = try? context.fetch(descriptor) else { return [:] }

        var result: [UUID: Date] = [:]
        for entry in entries {
            let exerciseID = entry.exercise.id
            if result[exerciseID] == nil {
                result[exerciseID] = entry.performedAt
            }
        }
        return result
    }

    private static func hasPrefix(_ name: String, _ needle: String) -> Bool {
        name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}

// MARK: - Spotlight

/// Pushes the exercise library into Spotlight's semantic index.
///
/// `IndexedEntity` is the documented route for the rebuilt Siri to reach in-app
/// content: indexed entities become searchable *and* become candidates Siri can
/// pass straight into `LogSetIntent`. Indexing is idempotent — re-running it
/// refreshes existing items rather than duplicating them.
@MainActor
enum ExerciseSpotlightIndex {
    /// Reindex the whole library. Cheap at this scale (tens of rows) and far more
    /// robust than trying to track per-row deltas across edits, deletes, seeding
    /// and store recovery.
    ///
    /// Call this after the container is up and after bulk changes (seed, import,
    /// restore). Failures are swallowed on purpose: a missing Spotlight entry must
    /// never block logging.
    static func reindexAll() async {
        // Indexing perturbs nothing visible, but it does mutate global system state
        // — keep it out of the UI-test harness like every other ambient surface.
        guard !TestHooks.isUITesting else { return }

        let context = AppIntentsSupport.resolvedContainer().mainContext
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        guard let exercises = try? context.fetch(descriptor), !exercises.isEmpty else { return }
        let entities = exercises.map(ExerciseEntity.init)

        do {
            try await CSSearchableIndex.default().indexAppEntities(entities)
        } catch {
            #if DEBUG
            print("Spotlight indexing failed: \(error)")
            #endif
        }
    }

    /// Drops one deleted exercise from the index, immediately.
    ///
    /// Per-item on purpose: `reindexAll()` refreshes rows that still exist but
    /// never removes one that doesn't, so "delete, then reindex" would leave
    /// the ghost searchable until the next cold launch — the stale-entry
    /// defect this closes. Failures are swallowed for the same reason as
    /// above: Spotlight hygiene must never block the delete itself.
    static func remove(exerciseID: UUID) async {
        guard !TestHooks.isUITesting else { return }

        do {
            try await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: [exerciseID],
                ofType: ExerciseEntity.self
            )
        } catch {
            #if DEBUG
            print("Spotlight de-indexing failed: \(error)")
            #endif
        }
    }

    /// Drops every indexed exercise. Used when the user wipes their data so
    /// Spotlight can't keep surfacing rows that no longer exist.
    static func removeAll() async {
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: ExerciseEntity.self)
        } catch {
            #if DEBUG
            print("Spotlight de-indexing failed: \(error)")
            #endif
        }
    }
}
