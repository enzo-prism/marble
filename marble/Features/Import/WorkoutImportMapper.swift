import Foundation
import SwiftData

enum WorkoutImportMapper {
    static func importNote(for record: WorkoutImportRecord) -> String {
        var parts = ["Imported from \(record.source.displayName)"]
        if let calories = record.calories, calories > 0 {
            parts.append("\(Int(calories)) kcal")
        }
        if let hr = record.averageHeartRate, hr > 0 {
            parts.append("\(Int(hr)) bpm avg")
        }
        return parts.joined(separator: " · ")
    }

    static func inferredCategory(for name: String) -> ExerciseCategory {
        let n = name.lowercased()
        if n.contains("bench") || n.contains("chest") || n.contains("dip") { return .chest }
        if n.contains("squat") || n.contains("leg") || n.contains("lunge") || n.contains("quad") || n.contains("leg press") { return .quads }
        if n.contains("deadlift") || n.contains("rdl") || n.contains("hamstring") || n.contains("good morning") { return .hamstrings }
        if n.contains("calf") { return .calves }
        if n.contains("row") || n.contains("pull") || n.contains("lat") || n.contains("back") { return .back }
        if n.contains("curl") || n.contains("bicep") { return .biceps }
        if n.contains("triceps") || n.contains("pushdown") || n.contains("skull") || n.contains("extension") && n.contains("tri") { return .triceps }
        if n.contains("press") || n.contains("shoulder") || n.contains("lateral") || n.contains("raise") || n.contains("overhead") { return .shoulders }
        if n.contains("plank") || n.contains("crunch") || n.contains("sit") || n.contains("core") || n.contains("hanging") { return .core }
        if n.contains("run") || n.contains("jog") { return .run }
        return .other
    }

    static func resolveExercise(
        name: String,
        category: ExerciseCategory,
        metrics: ExerciseMetricsProfile,
        defaultRestSeconds: Int,
        in context: ModelContext
    ) throws -> Exercise {
        try Resolver(in: context).resolve(
            name: name,
            category: category,
            metrics: metrics,
            defaultRestSeconds: defaultRestSeconds
        )
    }

    /// Batch-internal resolver that loads all exercises once and reuses the
    /// case-insensitive name index for every set in a single workout, instead
    /// of scanning the table once per `ImportedStrengthSet`.
    private struct Resolver {
        let context: ModelContext
        private var cache: [String: Exercise] = [:]

        init(in context: ModelContext) {
            self.context = context
        }

        mutating func resolve(
            name: String,
            category: ExerciseCategory,
            metrics: ExerciseMetricsProfile,
            defaultRestSeconds: Int
        ) throws -> Exercise {
            let key = name.lowercased()
            if let cached = cache[key] {
                return cached
            }

            let descriptor = FetchDescriptor<Exercise>()
            let existing = try context.fetch(descriptor)
            if let match = existing.first(where: { $0.name.lowercased() == key }) {
                cache[key] = match
                return match
            }

            let exercise = Exercise(
                name: name,
                category: category,
                metrics: metrics,
                defaultRestSeconds: defaultRestSeconds
            )
            context.insert(exercise)
            cache[key] = exercise
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
