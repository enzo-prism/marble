import Foundation
import SwiftData

enum TestFixtures {
    static func seedEmpty(in context: ModelContext, now: Date) {
        clear(context)
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)
    }

    static func seed(in context: ModelContext, now: Date) {
        clear(context)
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)

        let longNameExercise = Exercise(
            name: "Single Arm Dumbbell Bulgarian Split Squat (Paused)",
            category: .legs,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120,
            isFavorite: true,
            createdAt: now
        )
        context.insert(longNameExercise)

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        guard
            let bench = exerciseByName["Bench Press"],
            let pushUps = exerciseByName["Push Ups"],
            let plank = exerciseByName["Plank"],
            let sauna = exerciseByName["Sauna"],
            let squat = exerciseByName["Squat"],
            let dips = exerciseByName["Dips"]
        else {
            return
        }

        let calendar = Calendar.current
        func at(days: Int, hour: Int, minute: Int) -> Date {
            let start = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: days, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let entries: [SetEntry] = [
            SetEntry(
                exercise: bench,
                performedAt: at(days: 0, hour: 9, minute: 15),
                weight: 185,
                weightUnit: .lb,
                reps: 5,
                durationSeconds: nil,
                difficulty: 8,
                restAfterSeconds: 90,
                notes: "Felt strong",
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: pushUps,
                performedAt: at(days: 0, hour: 18, minute: 40),
                weight: nil,
                weightUnit: .lb,
                reps: 20,
                durationSeconds: nil,
                difficulty: 6,
                restAfterSeconds: 60,
                notes: nil,
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: plank,
                performedAt: at(days: -1, hour: 12, minute: 5),
                weight: nil,
                weightUnit: .lb,
                reps: nil,
                durationSeconds: 60,
                difficulty: 7,
                restAfterSeconds: 45,
                notes: nil,
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: longNameExercise,
                performedAt: at(days: -2, hour: 16, minute: 20),
                weight: 999.5,
                weightUnit: .lb,
                reps: 999,
                durationSeconds: nil,
                difficulty: 10,
                restAfterSeconds: 999,
                notes: "Extreme volume",
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: squat,
                performedAt: at(days: -3, hour: 8, minute: 30),
                weight: 225,
                weightUnit: .lb,
                reps: 3,
                durationSeconds: nil,
                difficulty: 9,
                restAfterSeconds: 150,
                notes: nil,
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: dips,
                performedAt: at(days: -4, hour: 7, minute: 45),
                weight: 45,
                weightUnit: .lb,
                reps: 10,
                durationSeconds: nil,
                difficulty: 5,
                restAfterSeconds: 90,
                notes: nil,
                createdAt: now,
                updatedAt: now
            ),
            SetEntry(
                exercise: sauna,
                performedAt: at(days: -7, hour: 20, minute: 10),
                weight: nil,
                weightUnit: .lb,
                reps: nil,
                durationSeconds: 900,
                difficulty: 1,
                restAfterSeconds: 0,
                notes: "Recovery",
                createdAt: now,
                updatedAt: now
            )
        ]

        entries.forEach { context.insert($0) }

        let supplements = (try? context.fetch(FetchDescriptor<SupplementType>())) ?? []
        let supplementsByName = Dictionary(uniqueKeysWithValues: supplements.map { ($0.name, $0) })

        if let creatine = supplementsByName["Creatine"] {
            context.insert(SupplementEntry(
                type: creatine,
                takenAt: at(days: 0, hour: 7, minute: 30),
                dose: 5,
                unit: .g,
                notes: "With water",
                createdAt: now,
                updatedAt: now
            ))
        }

        if let protein = supplementsByName["Protein Powder"] {
            context.insert(SupplementEntry(
                type: protein,
                takenAt: at(days: -1, hour: 10, minute: 15),
                dose: 1,
                unit: .scoop,
                notes: "Chocolate",
                createdAt: now,
                updatedAt: now
            ))
        }
    }

    private static func clear(_ context: ModelContext) {
        let sets = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        let supplements = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let supplementTypes = (try? context.fetch(FetchDescriptor<SupplementType>())) ?? []

        sets.forEach { context.delete($0) }
        supplements.forEach { context.delete($0) }
        exercises.forEach { context.delete($0) }
        supplementTypes.forEach { context.delete($0) }
    }
}
