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

    // ── Properties Siri can read ────────────────────────────────────────────
    // These are what let Siri answer "what's my bench PR?" or "when did I last
    // squat?" straight from the entity, with no intent of its own. Every value
    // is a preformatted string or a plain value computed once at construction,
    // so nothing here reads SwiftData off the main actor.
    //
    // `nonisolated(unsafe)` because `@Property` is a property wrapper and the
    // struct is `nonisolated` (see above): Swift 6 refuses `nonisolated` on a
    // wrapped mutable stored property. The values are written once in `init`
    // and never mutated, and `EntityProperty` is itself `Sendable`.
    //
    // Property `description:` arguments only exist in the Siri AI Developer
    // Preview SDK (Xcode 27.3 beta), hence the `SIRI_AI_PREVIEW` split — see
    // `SiriAIPreview/README.md`.

    #if SIRI_AI_PREVIEW
    @Property(title: "Favorite", description: "Whether the lifter starred this exercise in their library.")
    #else
    @Property(title: "Favorite")
    #endif
    nonisolated(unsafe) var isFavorite: Bool

    #if SIRI_AI_PREVIEW
    @Property(title: "Last Performed", description: "When the most recent set of this exercise was logged. Empty if it has never been logged.")
    #else
    @Property(title: "Last Performed")
    #endif
    nonisolated(unsafe) var lastPerformedAt: Date?

    #if SIRI_AI_PREVIEW
    @Property(title: "Total Sets", description: "How many sets of this exercise have ever been logged.")
    #else
    @Property(title: "Total Sets")
    #endif
    nonisolated(unsafe) var totalSets: Int

    #if SIRI_AI_PREVIEW
    @Property(title: "Heaviest Set", description: "The personal-best heaviest set, e.g. \"225 lb × 5\". For dumbbell-pair exercises the weight is per dumbbell with the total in parentheses. Empty if no weighted set exists.")
    #else
    @Property(title: "Heaviest Set")
    #endif
    nonisolated(unsafe) var heaviestSet: String?

    #if SIRI_AI_PREVIEW
    @Property(title: "Most Reps", description: "The personal-best set with the most reps, e.g. \"12 reps at 135 lb\". Empty if no set with reps exists.")
    #else
    @Property(title: "Most Reps")
    #endif
    nonisolated(unsafe) var mostRepsSet: String?

    #if SIRI_AI_PREVIEW
    @Property(title: "Usual Range", description: "The lifter's typical weight and reps over their recent sets, e.g. \"185–205 lb, 5–8 reps\". Empty until there are at least two recent sets.")
    #else
    @Property(title: "Usual Range")
    #endif
    nonisolated(unsafe) var usualRange: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(categoryName)")
    }

    init(
        id: UUID,
        name: String,
        categoryName: String,
        isFavorite: Bool = false,
        lastPerformedAt: Date? = nil,
        totalSets: Int = 0,
        heaviestSet: String? = nil,
        mostRepsSet: String? = nil,
        usualRange: String? = nil
    ) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.isFavorite = isFavorite
        self.lastPerformedAt = lastPerformedAt
        self.totalSets = totalSets
        self.heaviestSet = heaviestSet
        self.mostRepsSet = mostRepsSet
        self.usualRange = usualRange
    }
}

extension ExerciseEntity {
    /// Main-actor because reading a SwiftData model is a main-actor operation here;
    /// everything it copies out is a plain value.
    ///
    /// `history` is every set of *this* exercise when the caller already has it
    /// (`entities(for:in:)` batches one fetch for a whole list); otherwise it is
    /// fetched through the exercise's own context.
    @MainActor
    init(_ exercise: Exercise, history: [SetEntry]? = nil) {
        let entries = history ?? Self.history(for: exercise)
        let records = PersonalRecords.records(for: exercise, entries: entries)
        self.init(
            id: exercise.id,
            name: exercise.name,
            categoryName: exercise.category.displayName,
            isFavorite: exercise.isFavorite,
            lastPerformedAt: entries.map(\.performedAt).max(),
            totalSets: records.totalSets,
            heaviestSet: records.heaviestEntry.flatMap { Self.heaviestSummary($0, exercise: exercise) },
            mostRepsSet: records.mostRepsEntry.flatMap { Self.mostRepsSummary($0, exercise: exercise) },
            usualRange: Self.usualRangeSummary(records)
        )
    }

    /// One `SetEntry` fetch for a whole list of exercises — the Spotlight
    /// reindex and every query build tens of entities at once, and a fetch per
    /// exercise would scale with library size on every cold launch.
    @MainActor
    static func entities(for exercises: [Exercise], in context: ModelContext) -> [ExerciseEntity] {
        let all = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        let byExercise = Dictionary(grouping: all) { $0.exercise.id }
        return exercises.map { ExerciseEntity($0, history: byExercise[$0.id] ?? []) }
    }

    @MainActor
    private static func history(for exercise: Exercise) -> [SetEntry] {
        guard let context = exercise.modelContext else { return [] }
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.exercise.id == exerciseID })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// "225 lb × 5" — `formattedWeightSummary` keeps the dumbbell case honest
    /// ("40 lb each (80 lb total)"), the same wording `LogSetIntent` speaks.
    @MainActor
    private static func heaviestSummary(_ entry: SetEntry, exercise: Exercise) -> String? {
        guard let weight = entry.weight, weight > 0 else { return nil }
        let load = exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
        guard let reps = entry.reps, reps > 0 else { return load }
        return "\(load) × \(reps)"
    }

    @MainActor
    private static func mostRepsSummary(_ entry: SetEntry, exercise: Exercise) -> String? {
        guard let reps = entry.reps, reps > 0 else { return nil }
        let repsText = reps == 1 ? "1 rep" : "\(reps) reps"
        guard let weight = entry.weight, weight > 0 else { return repsText }
        return "\(repsText) at \(exercise.formattedWeightSummary(weight, unit: entry.weightUnit))"
    }

    /// Display-space range (per dumbbell for pairs), exactly what the logging
    /// screen's "usual range" shows.
    @MainActor
    private static func usualRangeSummary(_ records: ExercisePersonalRecords) -> String? {
        var parts: [String] = []
        if let range = records.usualWeightRange, let unit = records.usualWeightUnit {
            parts.append("\(formatted(range.lowerBound))–\(formatted(range.upperBound)) \(unit.symbol)")
        }
        if let reps = records.usualRepsRange {
            parts.append("\(reps.lowerBound)–\(reps.upperBound) reps")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    @MainActor
    private static func formatted(_ value: Double) -> String {
        Formatters.weight.string(from: NSNumber(value: value)) ?? "\(value)"
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
            try Self.allExercises().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Preserve the caller's order — Shortcuts renders these in the order it asked.
        return try Self.makeEntities(identifiers.compactMap { byID[$0] })
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

        let matches = try Self.allExercises().filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        // Prefix matches first ("bench" → "Bench Press" before "Close-Grip Bench"),
        // then alphabetical so the list is stable across launches.
        let sorted = matches
            .sorted { lhs, rhs in
                let lhsPrefix = Self.hasPrefix(lhs.name, needle)
                let rhsPrefix = Self.hasPrefix(rhs.name, needle)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return try Self.makeEntities(sorted)
    }

    /// Favorites first, then everything else — each group ordered by the exercise's
    /// most recent `SetEntry.performedAt` (never-logged exercises sort last within
    /// their group, then alphabetically so the order is stable).
    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let exercises = try Self.allExercises()
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

        return ExerciseEntity.entities(for: Array(ranked.prefix(Self.suggestionLimit)), in: context)
    }

    // MARK: - Fetch helpers

    @MainActor
    private static func makeEntities(_ exercises: [Exercise]) throws -> [ExerciseEntity] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        return ExerciseEntity.entities(for: exercises, in: context)
    }

    @MainActor
    private static func allExercises() throws -> [Exercise] {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
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
///
/// Rebuild-after-corruption: App Intents has no `IndexedEntityQuery`
/// (`reindexAllEntities()` / `reindexEntities(for:)`) in this SDK — the
/// iOS 26.5 `AppIntents.swiftinterface` declares no such protocol — so there
/// is nothing for `ExerciseQuery` to conform to. Recovery therefore stays
/// `reindexAll()` on every cold launch (`ContentView`'s `.task`), which at
/// this library's scale rebuilds the whole index anyway. CoreSpotlight's
/// delegate-level rebuild hooks exist but are item-based, not entity-based,
/// and are deliberately not mixed in here.
@MainActor
enum ExerciseSpotlightIndex {
    /// The one client index every call below goes through. Named because
    /// Apple documents `CSSearchableIndex.default()` as a prototyping
    /// convenience; `indexAppEntities`/`deleteAppEntities` are instance
    /// methods on `CSSearchableIndex`, so a named index takes them cleanly.
    /// Every named index writes into the same on-device store keyed by entity
    /// type + identifier, so rows indexed by earlier builds through the
    /// default index are upserted and deleted by these calls, not duplicated.
    /// Built inside each `nonisolated` helper below rather than held as a
    /// static: `CSSearchableIndex` is not `Sendable`, so a shared instance read
    /// on the main actor and then awaited on would be sent across isolation
    /// (an error under the Swift 6 language mode). Every named index writes into
    /// the same on-device store, so a per-call instance indexes identically.
    private nonisolated static func makeIndex() -> CSSearchableIndex {
        CSSearchableIndex(name: "ExerciseEntities")
    }
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

        guard let context = try? AppIntentsSupport.resolvedContainer().mainContext else { return }
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        guard let exercises = try? context.fetch(descriptor), !exercises.isEmpty else { return }
        let entities = ExerciseEntity.entities(for: exercises, in: context)

        await indexEntities(entities)
    }

    private nonisolated static func indexEntities(_ entities: [ExerciseEntity]) async {
        do {
            try await makeIndex().indexAppEntities(entities)
        } catch {
            #if DEBUG
            print("Spotlight indexing failed: \(error)")
            #endif
        }
    }

    /// Reindexes Spotlight **and** re-registers the parameterised shortcut
    /// phrases after a bulk library change (an import, a scan, a restore).
    ///
    /// Both halves are needed: the reindex makes the new exercise findable in
    /// Spotlight, and `updateAppShortcutParameters()` is what Apple requires
    /// whenever the entities behind a parameterised phrase change — without it
    /// "Log a set of <imported exercise>" does not resolve. Before this existed,
    /// no import path called either, so an auto-created exercise only became
    /// reachable from outside the app at the next cold launch.
    ///
    /// No-op until the app has published its container. Unit tests never set
    /// `AppIntentsSupport.container`, and without that guard a test-host import
    /// would spin up an on-disk store just to index it.
    static func refreshAfterLibraryChange() async {
        guard !TestHooks.isUITesting, AppIntentsSupport.container != nil else { return }
        await reindexAll()
        MarbleShortcuts.updateAppShortcutParameters()
    }

    private static var pendingSaveRefresh: Task<Void, Never>?

    /// Debounced `reindexAll()` after the journal saves in the app. The indexed
    /// entities carry set-derived values (heaviest set, usual range, last performed,
    /// total sets), so without this a logged, edited or deleted set left Spotlight
    /// and background Siri answering with the old personal best until the next cold
    /// launch. One save burst (a workout's sets, an undo) costs one reindex.
    static func scheduleRefreshAfterSave() {
        guard !TestHooks.isUITesting, AppIntentsSupport.container != nil else { return }
        pendingSaveRefresh?.cancel()
        pendingSaveRefresh = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await reindexAll()
        }
    }

    /// Immediate, awaited variant for intents. Siri can run them with no scene, so
    /// `ContentView`'s save observer may not exist and a debounced task could be
    /// suspended with the process; `perform()` awaits this before returning instead.
    static func refreshAfterSetChange() async {
        guard !TestHooks.isUITesting, AppIntentsSupport.container != nil else { return }
        pendingSaveRefresh?.cancel()
        await reindexAll()
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

        await deleteEntity(exerciseID: exerciseID)
    }

    private nonisolated static func deleteEntity(exerciseID: UUID) async {
        do {
            try await makeIndex().deleteAppEntities(
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
        await deleteAllEntities()
    }

    private nonisolated static func deleteAllEntities() async {
        do {
            try await makeIndex().deleteAppEntities(ofType: ExerciseEntity.self)
        } catch {
            #if DEBUG
            print("Spotlight de-indexing failed: \(error)")
            #endif
        }
    }
}
