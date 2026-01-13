import Foundation
import SwiftData
@testable import marble

enum SnapshotFixtures {
    static let now: Date = ISO8601DateFormatter().date(from: "2025-01-15T12:00:00Z")!

    static func makeContainer() -> ModelContainer {
        PersistenceController.makeContainer(useInMemory: true)
    }

    static func seedBase(in context: ModelContext) {
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)
        try? context.save()
    }

    static func seedPopulated(in context: ModelContext) {
        TestFixtures.seed(in: context, now: now)
        try? context.save()
    }

    static func exercise(named name: String, in context: ModelContext) -> Exercise {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if let match = exercises.first(where: { $0.name == name }) {
            return match
        }
        let new = Exercise(name: name, category: .other, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        context.insert(new)
        try? context.save()
        return new
    }

    static func addSet(
        in context: ModelContext,
        exerciseName: String,
        performedAt: Date,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        difficulty: Int = 8,
        restAfterSeconds: Int = 60
    ) {
        let exercise = exercise(named: exerciseName, in: context)
        let entry = SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: weight,
            weightUnit: .lb,
            reps: reps,
            durationSeconds: durationSeconds,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: nil,
            createdAt: performedAt,
            updatedAt: performedAt
        )
        context.insert(entry)
        try? context.save()
    }
}
