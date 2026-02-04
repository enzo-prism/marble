import Foundation
import SwiftData

enum TestFixtures {
    static func seedEmpty(in context: ModelContext, now: Date) {
        clear(context)
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)
        seedSplit(in: context, now: now, populated: false)
    }

    static func seed(in context: ModelContext, now: Date) {
        clear(context)
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)
        seedSplit(in: context, now: now, populated: true)

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
            let creatineEntries: [(Int, Int, Int, Double?, String?)] = [
                (0, 7, 30, 5, "With water"),
                (-1, 7, 20, 5, nil),
                (-2, 7, 45, 4.5, nil),
                (-3, 8, 0, nil, "Forgot to measure"),
                (-5, 7, 15, 5, nil)
            ]
            for entry in creatineEntries {
                context.insert(SupplementEntry(
                    type: creatine,
                    takenAt: at(days: entry.0, hour: entry.1, minute: entry.2),
                    dose: entry.3,
                    unit: .g,
                    notes: entry.4,
                    createdAt: now,
                    updatedAt: now
                ))
            }
        }

        if let protein = supplementsByName["Protein Powder"] {
            let proteinEntries: [(Int, Int, Int, Double?, String?)] = [
                (0, 9, 15, 1, "Vanilla"),
                (-2, 10, 15, 1.5, "Post workout"),
                (-4, 11, 5, 1, "Chocolate")
            ]
            for entry in proteinEntries {
                context.insert(SupplementEntry(
                    type: protein,
                    takenAt: at(days: entry.0, hour: entry.1, minute: entry.2),
                    dose: entry.3,
                    unit: .scoop,
                    notes: entry.4,
                    createdAt: now,
                    updatedAt: now
                ))
            }
        }
    }

    private static func clear(_ context: ModelContext) {
        let sets = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        let supplements = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let supplementTypes = (try? context.fetch(FetchDescriptor<SupplementType>())) ?? []
        let splitPlans = (try? context.fetch(FetchDescriptor<SplitPlan>())) ?? []
        let splitDays = (try? context.fetch(FetchDescriptor<SplitDay>())) ?? []
        let plannedSets = (try? context.fetch(FetchDescriptor<PlannedSet>())) ?? []

        sets.forEach { context.delete($0) }
        supplements.forEach { context.delete($0) }
        exercises.forEach { context.delete($0) }
        supplementTypes.forEach { context.delete($0) }
        plannedSets.forEach { context.delete($0) }
        splitDays.forEach { context.delete($0) }
        splitPlans.forEach { context.delete($0) }
    }

    private static func seedSplit(in context: ModelContext, now: Date, populated: Bool) {
        let plan = SplitPlan(name: "Current Split", isActive: true, createdAt: now, updatedAt: now)
        let titles: [String] = populated
            ? ["Push", "Pull", "Legs", "Rest", "Upper", "Lower", "Mobility"]
            : Array(repeating: "", count: Weekday.allCases.count)
        let notes: [String?] = populated
            ? ["Chest + triceps", "Back + biceps", "Quads + glutes", "Recovery day", "Strength focus", "Deadlift focus", "Stretch + core"]
            : Array(repeating: nil, count: Weekday.allCases.count)

        let days = Weekday.allCases.enumerated().map { index, weekday in
            SplitDay(
                weekday: weekday,
                title: titles[index],
                notes: notes[index],
                order: index,
                createdAt: now,
                updatedAt: now,
                plan: plan
            )
        }
        plan.days = days
        context.insert(plan)

        guard populated else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })

        if let monday = days.first(where: { $0.weekday == .monday }),
           let bench = exerciseByName["Bench Press"],
           let dips = exerciseByName["Dips"] {
            let first = PlannedSet(order: 0, notes: nil, createdAt: now, updatedAt: now, exercise: bench, day: monday)
            let second = PlannedSet(order: 1, notes: nil, createdAt: now, updatedAt: now, exercise: dips, day: monday)
            monday.plannedSets = [first, second]
            context.insert(first)
            context.insert(second)
        }

        if let tuesday = days.first(where: { $0.weekday == .tuesday }),
           let row = exerciseByName["Cable Row"] {
            let set = PlannedSet(order: 0, notes: nil, createdAt: now, updatedAt: now, exercise: row, day: tuesday)
            tuesday.plannedSets = [set]
            context.insert(set)
        }

        if let wednesday = days.first(where: { $0.weekday == .wednesday }),
           let squat = exerciseByName["Squat"],
           let calf = exerciseByName["Calf Raises"] {
            let first = PlannedSet(order: 0, notes: nil, createdAt: now, updatedAt: now, exercise: squat, day: wednesday)
            let second = PlannedSet(order: 1, notes: nil, createdAt: now, updatedAt: now, exercise: calf, day: wednesday)
            wednesday.plannedSets = [first, second]
            context.insert(first)
            context.insert(second)
        }
    }
}
