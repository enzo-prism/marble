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

        seedImportedWorkout(in: context, at: at(days: -1, hour: 7, minute: 30))

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

    /// Realistic five-week training history used for App Store screenshots:
    /// a weekly push/pull/legs split with steady progression, Sunday recovery,
    /// and daily supplements so every tab presents well-populated, plausible data.
    static func seedScreenshots(in context: ModelContext, now: Date) {
        clear(context)
        SeedData.seedExercises(in: context)
        SeedData.seedSupplements(in: context)
        seedSplit(in: context, now: now, populated: true)

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        let calendar = Calendar.current

        func at(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let start = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        struct ScreenshotSet {
            let exercise: String
            var weight: Double? = nil
            var reps: Int? = nil
            var distance: Double? = nil
            var durationSeconds: Int? = nil
            var difficulty: Int = 8
            var rest: Int = 90
            var notes: String? = nil
        }

        var minuteCursor = 0
        func insert(_ set: ScreenshotSet, daysAgo: Int) {
            guard let exercise = exerciseByName[set.exercise] else { return }
            let performedAt = at(daysAgo: daysAgo, hour: 7 + minuteCursor / 60, minute: 30 + minuteCursor % 60)
            minuteCursor += 4
            context.insert(SetEntry(
                exercise: exercise,
                performedAt: performedAt,
                weight: set.weight,
                weightUnit: .lb,
                reps: set.reps,
                distance: set.distance,
                distanceUnit: .meters,
                durationSeconds: set.durationSeconds,
                difficulty: set.difficulty,
                restAfterSeconds: set.rest,
                notes: set.notes,
                createdAt: performedAt,
                updatedAt: performedAt
            ))
        }

        for daysAgo in 0...34 {
            let day = at(daysAgo: daysAgo, hour: 12, minute: 0)
            let weekday = calendar.component(.weekday, from: day)
            // Older weeks lift slightly less so Trends shows real progression.
            let progress = Double((34 - daysAgo) / 7) * 5

            minuteCursor = 0
            let sets: [ScreenshotSet]
            switch weekday {
            case 2, 5: // Monday, Thursday: push
                sets = [
                    ScreenshotSet(exercise: "Bench Press", weight: 185 + progress, reps: 5, difficulty: 8, rest: 120, notes: daysAgo == 0 ? "Felt strong" : nil),
                    ScreenshotSet(exercise: "Bench Press", weight: 185 + progress, reps: 5, difficulty: 8, rest: 120),
                    ScreenshotSet(exercise: "Bench Press", weight: 190 + progress, reps: 4, difficulty: 9, rest: 120),
                    ScreenshotSet(exercise: "Shoulder Press", weight: 95 + progress / 2, reps: 8, difficulty: 7, rest: 90),
                    ScreenshotSet(exercise: "Shoulder Press", weight: 95 + progress / 2, reps: 8, difficulty: 8, rest: 90),
                    ScreenshotSet(exercise: "Dips", weight: 25, reps: 10, difficulty: 7, rest: 90),
                    ScreenshotSet(exercise: "Dips", weight: 25, reps: 9, difficulty: 8, rest: 90)
                ]
            case 3, 6: // Tuesday, Friday: pull
                sets = [
                    ScreenshotSet(exercise: "Deadlift", weight: 275 + progress, reps: 5, difficulty: 8, rest: 180),
                    ScreenshotSet(exercise: "Deadlift", weight: 285 + progress, reps: 3, difficulty: 9, rest: 180),
                    ScreenshotSet(exercise: "Pull Ups", reps: 12, difficulty: 7, rest: 90),
                    ScreenshotSet(exercise: "Pull Ups", reps: 10, difficulty: 8, rest: 90),
                    ScreenshotSet(exercise: "Cable Row", weight: 150, reps: 10, difficulty: 7, rest: 120),
                    ScreenshotSet(exercise: "Cable Row", weight: 150, reps: 10, difficulty: 7, rest: 120)
                ]
            case 4, 7: // Wednesday, Saturday: legs + core
                sets = [
                    ScreenshotSet(exercise: "Squat", weight: 225 + progress, reps: 5, difficulty: 8, rest: 150),
                    ScreenshotSet(exercise: "Squat", weight: 225 + progress, reps: 5, difficulty: 8, rest: 150),
                    ScreenshotSet(exercise: "Squat", weight: 235 + progress, reps: 3, difficulty: 9, rest: 150, notes: daysAgo < 7 ? "New top set" : nil),
                    ScreenshotSet(exercise: "Calf Raises", weight: 90, reps: 12, difficulty: 6, rest: 60),
                    ScreenshotSet(exercise: "Calf Raises", weight: 90, reps: 12, difficulty: 6, rest: 60),
                    ScreenshotSet(exercise: "Plank", durationSeconds: 75, difficulty: 7, rest: 45),
                    ScreenshotSet(exercise: "Plank", durationSeconds: 70, difficulty: 8, rest: 45)
                ]
            default: // Sunday: recovery
                sets = [
                    ScreenshotSet(exercise: "Sauna", durationSeconds: 1200, difficulty: 1, rest: 0, notes: "Recovery")
                ]
            }

            for set in sets {
                insert(set, daysAgo: daysAgo)
            }
        }

        // Most recent entry is a run so the quick-log card and set logger
        // showcase distance + time logging.
        if let run = exerciseByName["Run"] {
            let performedAt = at(daysAgo: 0, hour: 10, minute: 5)
            context.insert(SetEntry(
                exercise: run,
                performedAt: performedAt,
                weight: nil,
                weightUnit: .lb,
                reps: nil,
                distance: 5,
                distanceUnit: .kilometers,
                durationSeconds: 1530,
                difficulty: 6,
                restAfterSeconds: 0,
                notes: "Easy 5K",
                createdAt: performedAt,
                updatedAt: performedAt
            ))
        }

        let supplements = (try? context.fetch(FetchDescriptor<SupplementType>())) ?? []
        let supplementsByName = Dictionary(uniqueKeysWithValues: supplements.map { ($0.name, $0) })

        for daysAgo in 0...34 {
            if let creatine = supplementsByName["Creatine"] {
                let takenAt = at(daysAgo: daysAgo, hour: 7, minute: 15)
                context.insert(SupplementEntry(
                    type: creatine,
                    takenAt: takenAt,
                    dose: 5,
                    unit: .g,
                    notes: nil,
                    createdAt: takenAt,
                    updatedAt: takenAt
                ))
            }

            let weekday = calendar.component(.weekday, from: at(daysAgo: daysAgo, hour: 12, minute: 0))
            if weekday != 1, let protein = supplementsByName["Protein Powder"] {
                let takenAt = at(daysAgo: daysAgo, hour: 9, minute: 30)
                context.insert(SupplementEntry(
                    type: protein,
                    takenAt: takenAt,
                    dose: 1,
                    unit: .scoop,
                    notes: daysAgo == 0 ? "Post workout" : nil,
                    createdAt: takenAt,
                    updatedAt: takenAt
                ))
            }
        }
    }

    /// One fully-detailed imported workout (a Garmin run bridged through Apple
    /// Health) with its linked journal entry, so UI tests and audits can walk
    /// the journal's imported badge, the set detail's imported section, and
    /// the import hub's history + detail sheet.
    private static func seedImportedWorkout(in context: ModelContext, at date: Date) {
        let running = Exercise(
            name: "Running",
            category: .run,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 0
        )
        context.insert(running)

        let workout = ImportedWorkout(
            source: .appleHealth,
            externalID: "fixture-garmin-run",
            title: "Running",
            workoutDate: date,
            setsImported: 1,
            kind: .running,
            originName: "Garmin",
            sourceAppName: "Garmin Connect",
            deviceName: "Forerunner 265",
            distanceMeters: 5200,
            durationSeconds: 1815,
            calories: 289,
            averageHeartRate: 152,
            maxHeartRate: 171,
            elevationAscendedMeters: 84,
            isIndoor: false
        )
        context.insert(workout)

        let entry = SetEntry(
            exercise: running,
            performedAt: date,
            distance: 5200,
            distanceUnit: .meters,
            durationSeconds: 1815,
            difficulty: 6,
            restAfterSeconds: 0,
            notes: "Imported from Garmin"
        )
        entry.importedWorkout = workout
        context.insert(entry)
    }

    private static func clear(_ context: ModelContext) {
        let sets = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        let supplements = (try? context.fetch(FetchDescriptor<SupplementEntry>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let supplementTypes = (try? context.fetch(FetchDescriptor<SupplementType>())) ?? []
        let splitPlans = (try? context.fetch(FetchDescriptor<SplitPlan>())) ?? []
        let splitDays = (try? context.fetch(FetchDescriptor<SplitDay>())) ?? []
        let plannedSets = (try? context.fetch(FetchDescriptor<PlannedSet>())) ?? []
        let customNotifications = (try? context.fetch(FetchDescriptor<CustomNotification>())) ?? []
        let importedWorkouts = (try? context.fetch(FetchDescriptor<ImportedWorkout>())) ?? []

        importedWorkouts.forEach { context.delete($0) }
        sets.forEach { context.delete($0) }
        supplements.forEach { context.delete($0) }
        exercises.forEach { context.delete($0) }
        supplementTypes.forEach { context.delete($0) }
        plannedSets.forEach { context.delete($0) }
        splitDays.forEach { context.delete($0) }
        splitPlans.forEach { context.delete($0) }
        customNotifications.forEach { context.delete($0) }
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
