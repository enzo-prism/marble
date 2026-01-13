import XCTest
import SwiftData
@testable import marble

final class SeedDataTests: XCTestCase {
    func testSeedExercisesExistAndEditable() throws {
        let container = PersistenceController.makeContainer(useInMemory: true)
        let context = ModelContext(container)

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
        let container = PersistenceController.makeContainer(useInMemory: true)
        let context = ModelContext(container)

        SeedData.seedSupplements(in: context)

        let types = try context.fetch(FetchDescriptor<SupplementType>())
        let names = Set(types.map { $0.name })
        XCTAssertTrue(names.contains("Creatine"))
        XCTAssertTrue(names.contains("Protein Powder"))
    }

    func testSeedSplitPlanCreatesWeek() throws {
        let container = PersistenceController.makeContainer(useInMemory: true)
        let context = ModelContext(container)

        SeedData.seedSplitPlan(in: context)

        let plans = try context.fetch(FetchDescriptor<SplitPlan>())
        XCTAssertEqual(plans.count, 1)
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.days.count, Weekday.allCases.count)
        let weekdays = Set(plan.days.map { $0.weekday })
        XCTAssertEqual(weekdays, Set(Weekday.allCases))
    }
}
