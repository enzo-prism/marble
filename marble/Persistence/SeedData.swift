import Foundation
import SwiftData

enum SeedData {
    private static let didSeedKey = "didSeedMarbleData"

    static func seedIfNeeded(in context: ModelContext) {
        if TestHooks.isUITesting {
            switch TestHooks.fixtureMode {
            case .empty:
                TestFixtures.seedEmpty(in: context, now: AppEnvironment.now)
            case .populated:
                TestFixtures.seed(in: context, now: AppEnvironment.now)
            }
            return
        }
        let defaults = UserDefaults.standard
        let didSeed = defaults.bool(forKey: didSeedKey)

        if !didSeed {
            let exerciseCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
            let supplementCount = (try? context.fetchCount(FetchDescriptor<SupplementType>())) ?? 0

            if exerciseCount == 0 {
                seedExercises(in: context)
            }

            if supplementCount == 0 {
                seedSupplements(in: context)
            }

            defaults.set(true, forKey: didSeedKey)
        }

        ensureSplitPlan(in: context)
    }

    static func seedExercises(in context: ModelContext) {
        let exercises = seedExerciseRows().map {
            Exercise(
                name: $0.name,
                category: $0.category,
                metrics: $0.metrics,
                defaultRestSeconds: $0.defaultRestSeconds
            )
        }
        exercises.forEach { context.insert($0) }
    }

    static func seedSupplements(in context: ModelContext) {
        let types = [
            SupplementType(name: "Creatine", defaultDose: 5, unit: .g, isFavorite: true),
            SupplementType(name: "Protein Powder", defaultDose: 1, unit: .scoop, isFavorite: true)
        ]
        types.forEach { context.insert($0) }
    }

    static func ensureSplitPlan(in context: ModelContext) {
        let planCount = (try? context.fetchCount(FetchDescriptor<SplitPlan>())) ?? 0
        if planCount == 0 {
            seedSplitPlan(in: context)
        }
    }

    static func seedSplitPlan(in context: ModelContext) {
        let now = AppEnvironment.now
        let plan = SplitPlan(name: "Current Split", isActive: true, createdAt: now, updatedAt: now)
        let days = Weekday.allCases.enumerated().map { index, weekday in
            SplitDay(
                weekday: weekday,
                title: "",
                notes: nil,
                order: index,
                createdAt: now,
                updatedAt: now,
                plan: plan
            )
        }
        plan.days = days
        context.insert(plan)
    }

    static func seedExerciseRows() -> [SeedExercise] {
        [
            // Chest
            SeedExercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Push Ups", category: .chest, metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), defaultRestSeconds: 60),
            SeedExercise(name: "DB Pec Fly", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90),
            SeedExercise(name: "Cable Pec Fly", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90),
            SeedExercise(name: "Dips", category: .chest, metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), defaultRestSeconds: 90),

            // Shoulders
            SeedExercise(name: "Shoulder Press", category: .shoulders, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Rear Delt Fly", category: .shoulders, metrics: .weightAndRepsRequired, defaultRestSeconds: 90),
            SeedExercise(name: "Cable Face Pull", category: .shoulders, metrics: .weightAndRepsRequired, defaultRestSeconds: 75),

            // Legs
            SeedExercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 150),
            SeedExercise(name: "Single Leg Squat", category: .legs, metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), defaultRestSeconds: 90),
            SeedExercise(name: "Good Morning", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Calf Raises", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 60),
            SeedExercise(name: "Calf Raises (Seated)", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 60),
            SeedExercise(name: "Glute Bridge", category: .legs, metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), defaultRestSeconds: 75),
            SeedExercise(name: "Jump Squat", category: .legs, metrics: .repsOnlyRequired, defaultRestSeconds: 75),

            // Power
            SeedExercise(name: "Hang Clean", category: .power, metrics: .weightAndRepsRequired, defaultRestSeconds: 180),
            SeedExercise(name: "Power Clean", category: .power, metrics: .weightAndRepsRequired, defaultRestSeconds: 180),
            SeedExercise(name: "Hang Snatch", category: .power, metrics: .weightAndRepsRequired, defaultRestSeconds: 180),
            SeedExercise(name: "Power Snatch", category: .power, metrics: .weightAndRepsRequired, defaultRestSeconds: 180),

            // Back
            SeedExercise(name: "Deadlift", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 180),
            SeedExercise(name: "Bent Over DB Row", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Cable Row", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Lat Pulldown", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Lat Pushdown", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 90),

            // Core
            SeedExercise(name: "Toe Touches", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Leg Lifts", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Crunches", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Side Flex", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Back Flex", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Bicycles", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Scissors", category: .core, metrics: .repsOnlyRequired, defaultRestSeconds: 45),
            SeedExercise(name: "Plank", category: .core, metrics: .durationOnlyRequired, defaultRestSeconds: 45),

            // Bar
            SeedExercise(name: "Pull Ups", category: .bar, metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), defaultRestSeconds: 90),
            SeedExercise(name: "True Bubka", category: .bar, metrics: .repsOnlyRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Wipers", category: .bar, metrics: .repsOnlyRequired, defaultRestSeconds: 120),
            SeedExercise(name: "Down Pressure", category: .bar, metrics: .repsOnlyRequired, defaultRestSeconds: 120),

            // Recover
            SeedExercise(name: "Sauna", category: .recover, metrics: .durationOnlyRequired, defaultRestSeconds: 0)
        ]
    }
}

struct SeedExercise {
    let name: String
    let category: ExerciseCategory
    let metrics: ExerciseMetricsProfile
    let defaultRestSeconds: Int
}
