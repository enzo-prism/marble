import XCTest
@testable import marble

final class EmpireEconomyTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func makeExercise() -> Exercise {
        Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func entry(
        _ exercise: Exercise,
        daysFromNow: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil
    ) -> SetEntry {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        let performedAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        return SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: weight,
            weightUnit: .lb,
            reps: reps,
            durationSeconds: durationSeconds,
            difficulty: 8,
            restAfterSeconds: 90
        )
    }

    // MARK: Currency

    func testLifetimeTalentsMatchVolumeScore() {
        let exercise = makeExercise()
        // 100×5 weighted = 500, plus 20 bodyweight reps = 20, plus 120s = 2 minutes.
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -1, reps: 20),
            entry(exercise, daysFromNow: -2, durationSeconds: 120)
        ]
        XCTAssertEqual(EmpireEconomy.lifetimeTalents(from: entries), 522, accuracy: 0.001)
    }

    func testVestSquatExampleMatchesUserIntuition() {
        // The user's model: a 10 lb vest × 10 squats banks 100 Talents.
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        let entries = [entry(exercise, daysFromNow: 0, weight: 10, reps: 10)]
        XCTAssertEqual(EmpireEconomy.lifetimeTalents(from: entries), 100, accuracy: 0.001)
    }

    func testTalentsEarnedTodayCountsOnlyToday() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),   // today: 500
            entry(exercise, daysFromNow: -1, weight: 100, reps: 5)   // yesterday: excluded
        ]
        XCTAssertEqual(EmpireEconomy.talentsEarned(on: now, from: entries, calendar: calendar), 500, accuracy: 0.001)
    }

    // MARK: Catalog integrity

    func testCatalogStructureIDsAreUnique() {
        let ids = EmpireEconomy.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryAgeHasStructures() {
        for age in EmpireAge.allCases {
            XCTAssertFalse(EmpireEconomy.structures(in: age).isEmpty, "\(age.title) has no structures")
        }
    }

    // MARK: Palette coverage (Empire is the one tab allowed colour; each age must define one)

    func testEveryAgeHasASkyGradientPalette() {
        for age in EmpireAge.allCases {
            XCTAssertGreaterThanOrEqual(
                age.palette.sky.count, 2,
                "\(age.title) needs at least a two-stop sky gradient"
            )
        }
    }

    func testAgesUseDistinctAccents() {
        // Colour doubles as a progression signal, so each era should read as its own world.
        let accents = EmpireAge.allCases.map { $0.palette.accent.description }
        XCTAssertEqual(accents.count, Set(accents).count, "Two ages share an accent colour")
    }

    func testCostsAscendWithinEachAge() {
        for age in EmpireAge.allCases {
            let costs = EmpireEconomy.structures(in: age).map(\.cost)
            XCTAssertEqual(costs, costs.sorted(), "\(age.title) costs are not ascending")
        }
    }

    // MARK: Age unlocking

    func testFoundationsAlwaysUnlocked() {
        XCTAssertTrue(EmpireEconomy.isAgeUnlocked(.foundations, builtIDs: []))
    }

    func testSecondAgeLockedUntilFirstComplete() {
        XCTAssertFalse(EmpireEconomy.isAgeUnlocked(.golden, builtIDs: ["quarry", "altar"]))

        let foundations = Set(EmpireEconomy.structures(in: .foundations).map(\.id))
        XCTAssertTrue(EmpireEconomy.isAgeComplete(.foundations, builtIDs: foundations))
        XCTAssertTrue(EmpireEconomy.isAgeUnlocked(.golden, builtIDs: foundations))
    }

    func testCurrentAgeAdvancesAsAgesComplete() {
        XCTAssertEqual(EmpireEconomy.currentAge(builtIDs: []), .foundations)

        let foundations = Set(EmpireEconomy.structures(in: .foundations).map(\.id))
        XCTAssertEqual(EmpireEconomy.currentAge(builtIDs: foundations), .golden)
    }

    func testNextGoalIsCheapestUnbuiltUnlockedStructure() {
        XCTAssertEqual(EmpireEconomy.nextGoal(builtIDs: [])?.id, "quarry")
        XCTAssertEqual(EmpireEconomy.nextGoal(builtIDs: ["quarry"])?.id, "altar")
    }

    func testNextGoalNilWhenEverythingBuilt() {
        let all = Set(EmpireEconomy.catalog.map(\.id))
        XCTAssertNil(EmpireEconomy.nextGoal(builtIDs: all))
    }

    // MARK: EmpireState purchasing

    func testPurchaseDeductsAndMarksBuilt() {
        let state = EmpireState(storedLifetimeTalents: 1_000)
        let quarry = EmpireEconomy.structure(id: "quarry")!

        XCTAssertTrue(state.purchase(quarry, now: now))
        XCTAssertEqual(state.spentTalents, 250, accuracy: 0.001)
        XCTAssertEqual(state.balance, 750, accuracy: 0.001)
        XCTAssertTrue(state.isBuilt("quarry"))
    }

    func testCannotPurchaseTwice() {
        let state = EmpireState(storedLifetimeTalents: 1_000)
        let quarry = EmpireEconomy.structure(id: "quarry")!

        XCTAssertTrue(state.purchase(quarry, now: now))
        XCTAssertFalse(state.purchase(quarry, now: now))
        XCTAssertEqual(state.spentTalents, 250, accuracy: 0.001)
    }

    func testCannotPurchaseWhenBalanceTooLow() {
        let state = EmpireState(storedLifetimeTalents: 100)
        let quarry = EmpireEconomy.structure(id: "quarry")! // costs 250

        XCTAssertFalse(state.purchase(quarry, now: now))
        XCTAssertEqual(state.spentTalents, 0, accuracy: 0.001)
        XCTAssertFalse(state.isBuilt("quarry"))
    }

    func testLifetimeTalentsAreMonotonic() {
        let state = EmpireState(storedLifetimeTalents: 5_000)
        state.updateLifetimeTalents(3_000) // a deletion would lower the computed value
        XCTAssertEqual(state.storedLifetimeTalents, 5_000, accuracy: 0.001)
        state.updateLifetimeTalents(8_000)
        XCTAssertEqual(state.storedLifetimeTalents, 8_000, accuracy: 0.001)
    }
}
