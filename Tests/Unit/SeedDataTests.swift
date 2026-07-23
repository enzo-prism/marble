import XCTest
import SwiftData
@testable import marble

final class SeedDataTests: MarbleTestCase {
    func testSeedExercisesExistAndEditable() throws {
        let context = makeInMemoryContext()

        SeedData.seedExercises(in: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertGreaterThanOrEqual(exercises.count, 1)

        let names = Set(exercises.map { $0.name })
        let expected = Set([
            "Bench Press",
            "Push Ups",
            "DB Pec Fly",
            "Cable Pec Fly",
            "Dips",
            "Shoulder Press",
            "Rear Delt Fly",
            "Cable Face Pull",
            "Squat",
            "Single Leg Squat",
            "Good Morning",
            "Calf Raises",
            "Calf Raises (Seated)",
            "Glute Bridge",
            "Jump Squat",
            "Hang Clean",
            "Power Clean",
            "Hang Snatch",
            "Power Snatch",
            "Deadlift",
            "Bent Over DB Row",
            "Cable Row",
            "Lat Pulldown",
            "Lat Pushdown",
            "Toe Touches",
            "Leg Lifts",
            "Crunches",
            "Side Flex",
            "Back Flex",
            "Bicycles",
            "Scissors",
            "Plank",
            "Pull Ups",
            "True Bubka",
            "Wipers",
            "Down Pressure",
            "Sauna"
        ])

        XCTAssertTrue(expected.isSubset(of: names))

        if let exercise = exercises.first {
            let updated = exercise.name + " Updated"
            exercise.name = updated
            XCTAssertEqual(exercise.name, updated)
        }
    }

    func testSeedSupplementTypesExist() throws {
        let context = makeInMemoryContext()

        SeedData.seedSupplements(in: context)

        let types = try context.fetch(FetchDescriptor<SupplementType>())
        let names = Set(types.map { $0.name })
        XCTAssertTrue(names.contains("Creatine"))
        XCTAssertTrue(names.contains("Protein Powder"))
    }

    func testSeedSplitPlanCreatesWeek() throws {
        let context = makeInMemoryContext()

        SeedData.seedSplitPlan(in: context)

        let plans = try context.fetch(FetchDescriptor<SplitPlan>())
        XCTAssertEqual(plans.count, 1)
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.days.count, Weekday.allCases.count)
        let weekdays = Set(plan.days.map { $0.weekday })
        XCTAssertEqual(weekdays, Set(Weekday.allCases))
    }

    func testOrphanMaintenanceRunsOncePerVersion() throws {
        let context = makeInMemoryContext()
        let suiteName = "SeedDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        func insertOrphans() throws {
            context.insert(SprintPrescription(
                exerciseID: UUID(),
                distance: 100,
                repetitionCount: 4,
                targetLowerSeconds: 12,
                targetUpperSeconds: 14
            ))
            context.insert(SprintGoalSnapshot(
                setEntryID: UUID(),
                exerciseID: UUID(),
                distance: 100,
                distanceUnit: .meters,
                repetitionNumber: 1,
                repetitionCount: 4,
                targetLowerSeconds: 12,
                targetUpperSeconds: 14
            ))
            try context.save()
        }

        try insertOrphans()
        SeedData.performOneTimeMaintenanceIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)

        try insertOrphans()
        SeedData.performOneTimeMaintenanceIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 1)
    }

    func testScreenshotFixtureUsesExerciseMatchedEmojiAndFeatureData() throws {
        let context = makeInMemoryContext()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T16:30:00Z"))

        TestFixtures.seedScreenshots(in: context, now: now)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        XCTAssertEqual(exerciseByName["Bench Press"]?.sanitizedCustomIconEmoji, "🏋️")
        XCTAssertEqual(exerciseByName["Squat"]?.sanitizedCustomIconEmoji, "🦵")
        XCTAssertEqual(exerciseByName["Plank"]?.sanitizedCustomIconEmoji, "🧱")
        XCTAssertEqual(exerciseByName["Run"]?.sanitizedCustomIconEmoji, "🏃")
        XCTAssertEqual(exerciseByName["Sprint"]?.sanitizedCustomIconEmoji, "💨")
        XCTAssertTrue(
            exercises.allSatisfy { $0.sanitizedCustomIconEmoji != nil },
            "Every exercise visible in App Store sample data should use an emoji icon."
        )

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(
            entries.allSatisfy { $0.performedAt <= now },
            "App Store sample data must not show future-dated workout entries."
        )

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.filter(\.isActive).first?.title, "Leg Day")
        XCTAssertGreaterThanOrEqual(sessions.filter(\.isActive).first?.entries.count ?? 0, 3)

        let imports = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(imports.first?.displayOrigin, "Garmin")

        let prescriptions = try context.fetch(FetchDescriptor<SprintPrescription>())
        XCTAssertEqual(prescriptions.first?.repetitionCount, 4)
        XCTAssertEqual(prescriptions.first?.distance, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 2)
    }
}
