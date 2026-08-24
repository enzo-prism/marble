import Foundation
import SwiftData

enum WorkoutImportMapper {
    /// The note is now just the provenance line — calories, heart rate, and the
    /// rest live as structured fields on the linked `ImportedWorkout`, where the
    /// journal detail view renders them properly instead of as note text.
    static func importNote(for record: WorkoutImportRecord) -> String {
        "Imported from \(record.displayOrigin)"
    }

    static func inferredCategory(for name: String) -> ExerciseCategory {
        let n = name.lowercased()
        if n.contains("bench") || n.contains("chest") || n.contains("dip") { return .chest }
        // Core is checked before legs so "Hanging Leg Raise" lands in core
        // instead of matching the generic "leg" keyword below.
        if n.contains("plank") || n.contains("crunch") || n.contains("sit") || n.contains("core") || n.contains("hanging") { return .core }
        // Specific leg movements before the broad "leg" keyword below: a leg curl trains
        // hamstrings, not quads.
        if n.contains("leg curl") || n.contains("hamstring curl") || n.contains("lying curl") { return .hamstrings }
        if n.contains("squat") || n.contains("leg") || n.contains("lunge") || n.contains("quad") || n.contains("leg press") { return .quads }
        if n.contains("deadlift") || n.contains("rdl") || n.contains("hamstring") || n.contains("good morning") { return .hamstrings }
        if n.contains("calf") { return .calves }
        if n.contains("row") || n.contains("pull") || n.contains("lat") || n.contains("back") { return .back }
        if n.contains("curl") || n.contains("bicep") { return .biceps }
        if n.contains("triceps") || n.contains("pushdown") || n.contains("skull") || n.contains("extension") && n.contains("tri") { return .triceps }
        if n.contains("press") || n.contains("shoulder") || n.contains("lateral") || n.contains("raise") || n.contains("overhead") { return .shoulders }
        if n.contains("run") || n.contains("jog") { return .run }
        return .other
    }

    static func resolveExercise(
        name: String,
        category: ExerciseCategory,
        metrics: ExerciseMetricsProfile,
        defaultRestSeconds: Int,
        libraryExerciseID: UUID? = nil,
        createNew: Bool = false,
        in context: ModelContext
    ) throws -> Exercise {
        var resolver = Resolver(in: context)
        return try resolver.resolve(
            name: name,
            category: category,
            metrics: metrics,
            defaultRestSeconds: defaultRestSeconds,
            libraryExerciseID: libraryExerciseID,
            createNew: createNew
        )
    }

    /// Batch-internal resolver that loads all exercises once and reuses the
    /// case-insensitive name index for every set in a single workout, instead
    /// of scanning the table once per `ImportedStrengthSet`.
    struct Resolver {
        let context: ModelContext
        private var automaticCache: [String: Exercise] = [:]
        private var libraryCache: [UUID: Exercise] = [:]
        private var newExerciseCache: [String: Exercise] = [:]
        private var allExercises: [Exercise]?

        init(in context: ModelContext) {
            self.context = context
        }

        mutating func resolve(
            name: String,
            category: ExerciseCategory,
            metrics: ExerciseMetricsProfile,
            defaultRestSeconds: Int,
            libraryExerciseID: UUID? = nil,
            createNew: Bool = false
        ) throws -> Exercise {
            let key = name.lowercased()

            if let libraryExerciseID {
                if let cached = libraryCache[libraryExerciseID] { return cached }
                let existing = try loadedExercises()
                if let match = existing.first(where: { $0.id == libraryExerciseID }) {
                    libraryCache[libraryExerciseID] = match
                    return match
                }
                // A library row can disappear while review is open. Preserve
                // the user's workout by creating the reviewed name instead of
                // silently attaching its sets to another duplicate-name row.
                return Self.makeExercise(
                    context: context,
                    name: name,
                    category: category,
                    metrics: metrics,
                    defaultRestSeconds: defaultRestSeconds,
                    cacheKey: key,
                    in: &newExerciseCache
                )
            }

            if createNew {
                return Self.makeExercise(
                    context: context,
                    name: name,
                    category: category,
                    metrics: metrics,
                    defaultRestSeconds: defaultRestSeconds,
                    cacheKey: key,
                    in: &newExerciseCache
                )
            }

            if let cached = automaticCache[key] {
                return cached
            }

            let existing = try loadedExercises()
            if let match = existing.first(where: { $0.name.lowercased() == key }) {
                automaticCache[key] = match
                return match
            }

            return Self.makeExercise(
                context: context,
                name: name,
                category: category,
                metrics: metrics,
                defaultRestSeconds: defaultRestSeconds,
                cacheKey: key,
                in: &automaticCache
            )
        }

        private mutating func loadedExercises() throws -> [Exercise] {
            if let allExercises { return allExercises }
            let fetched = try context.fetch(FetchDescriptor<Exercise>())
            allExercises = fetched
            return fetched
        }

        private static func makeExercise(
            context: ModelContext,
            name: String,
            category: ExerciseCategory,
            metrics: ExerciseMetricsProfile,
            defaultRestSeconds: Int,
            cacheKey: String,
            in cache: inout [String: Exercise]
        ) -> Exercise {
            if let cached = cache[cacheKey] { return cached }
            let exercise = Exercise(
                name: name,
                category: category,
                metrics: metrics,
                defaultRestSeconds: defaultRestSeconds
            )
            context.insert(exercise)
            cache[cacheKey] = exercise
            return exercise
        }
    }

    static func makeSetEntries(for record: WorkoutImportRecord, in context: ModelContext) throws -> [SetEntry] {
        let note = importNote(for: record)
        var resolver = Resolver(in: context)

        switch record.kind {
        case .strength:
            if record.strengthSets.isEmpty {
                let exercise = try resolver.resolve(
                    name: "Strength Training",
                    category: .other,
                    metrics: .durationOnlyRequired,
                    defaultRestSeconds: 60
                )
                let entry = SetEntry(
                    exercise: exercise,
                    performedAt: record.date,
                    durationSeconds: record.durationSeconds,
                    restAfterSeconds: 0,
                    notes: note
                )
                context.insert(entry)
                return [entry]
            }

            var entries: [SetEntry] = []
            for set in record.strengthSets {
                let category = inferredCategory(for: set.exerciseName)
                let exercise = try resolver.resolve(
                    name: set.exerciseName,
                    category: category,
                    metrics: .weightAndRepsRequired,
                    defaultRestSeconds: 60
                )
                let entry = SetEntry(
                    exercise: exercise,
                    performedAt: record.date,
                    weight: set.weightKilograms,
                    weightUnit: .kg,
                    reps: set.reps,
                    restAfterSeconds: set.restSeconds ?? exercise.defaultRestSeconds,
                    notes: note
                )
                context.insert(entry)
                entries.append(entry)
            }
            return entries

        default:
            let exercise = try resolver.resolve(
                name: record.kind.displayName,
                category: .run,
                metrics: .distanceAndDurationRequired,
                defaultRestSeconds: 0
            )
            let entry = SetEntry(
                exercise: exercise,
                performedAt: record.date,
                distance: record.distanceMeters,
                distanceUnit: .meters,
                durationSeconds: record.durationSeconds,
                restAfterSeconds: 0,
                notes: note
            )
            context.insert(entry)
            return [entry]
        }
    }
}
