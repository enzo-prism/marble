import XCTest
@testable import marble

final class PersonalRecordsTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    // MARK: - Badge trail

    func testBadgeTrailMarksEveryRecordBreaker() {
        let bench = makeBench()
        let first = set(bench, daysFromNow: -3, weight: 100, reps: 8)   // baseline weight + reps
        let second = set(bench, daysFromNow: -2, weight: 100, reps: 10) // reps PR only (weight tied)
        let third = set(bench, daysFromNow: -1, weight: 105, reps: 6)   // weight PR only

        let badges = PersonalRecords.badges(for: [third, first, second])

        XCTAssertEqual(badges[first.id], [.weight, .reps])
        XCTAssertEqual(badges[second.id], [.reps])
        XCTAssertEqual(badges[third.id], [.weight])
    }

    func testFirstSetIsBaselinePersonalRecord() {
        let bench = makeBench()
        let only = set(bench, daysFromNow: 0, weight: 135, reps: 5)

        let badges = PersonalRecords.badges(for: [only])

        XCTAssertEqual(badges[only.id], [.weight, .reps])
    }

    func testTiesAreNotRecords() {
        let bench = makeBench()
        let first = set(bench, daysFromNow: -1, weight: 100, reps: 8)
        let repeated = set(bench, daysFromNow: 0, weight: 100, reps: 8)

        let badges = PersonalRecords.badges(for: [first, repeated])

        XCTAssertEqual(badges[first.id], [.weight, .reps])
        XCTAssertNil(badges[repeated.id])
    }

    func testWeightRecordsNormalizeUnits() {
        let bench = makeBench()
        // 100 lb ≈ 45.36 kg, so 50 kg is genuinely heavier and should be a PR.
        let pounds = set(bench, daysFromNow: -1, weight: 100, reps: 5, unit: .lb)
        let kilos = set(bench, daysFromNow: 0, weight: 50, reps: 5, unit: .kg)

        let badges = PersonalRecords.badges(for: [pounds, kilos])

        XCTAssertTrue(badges[kilos.id]?.contains(.weight) ?? false)
    }

    func testHeavierNumberInLighterUnitIsNotRecord() {
        let bench = makeBench()
        // 100 kg is heavier than 200 lb (≈90.7 kg), so 200 lb is NOT a weight PR.
        let kilos = set(bench, daysFromNow: -1, weight: 100, reps: 3, unit: .kg)
        let pounds = set(bench, daysFromNow: 0, weight: 200, reps: 3, unit: .lb)

        let badges = PersonalRecords.badges(for: [kilos, pounds])

        XCTAssertFalse(badges[pounds.id]?.contains(.weight) ?? false)
    }

    func testCardioExerciseEarnsNoBadges() {
        let run = Exercise(name: "Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(
            exercise: run,
            performedAt: date(daysFromNow: 0),
            distance: 5,
            distanceUnit: .kilometers,
            durationSeconds: 1500,
            restAfterSeconds: 0
        )

        let badges = PersonalRecords.badges(for: [entry])

        XCTAssertTrue(badges.isEmpty)
    }

    func testBadgesAreScopedPerExercise() {
        let bench = makeBench()
        let squat = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let benchSet = set(bench, daysFromNow: -1, weight: 100, reps: 5)
        let squatSet = set(squat, daysFromNow: 0, weight: 80, reps: 5)

        let badges = PersonalRecords.badges(for: [benchSet, squatSet])

        // Each exercise's first set is its own baseline; one doesn't suppress the other.
        XCTAssertEqual(badges[benchSet.id], [.weight, .reps])
        XCTAssertEqual(badges[squatSet.id], [.weight, .reps])
    }

    // MARK: - All-time records + usual ranges

    func testRecordsTrackHeaviestAndMostRepsAllTime() {
        let bench = makeBench()
        let entries = [
            set(bench, daysFromNow: -4, weight: 95, reps: 6),
            set(bench, daysFromNow: -3, weight: 100, reps: 8),
            set(bench, daysFromNow: -2, weight: 105, reps: 6),
            set(bench, daysFromNow: -1, weight: 100, reps: 10),
            set(bench, daysFromNow: 0, weight: 102.5, reps: 7)
        ]

        let records = PersonalRecords.records(for: bench, entries: entries)

        XCTAssertEqual(records.heaviestEntry?.weight, 105)
        XCTAssertEqual(records.heaviestEntry?.reps, 6)
        XCTAssertEqual(records.mostRepsEntry?.reps, 10)
        XCTAssertEqual(records.mostRepsEntry?.weight, 100)
        XCTAssertEqual(records.usualWeightRange, 95...105)
        XCTAssertEqual(records.usualWeightUnit, .lb)
        XCTAssertEqual(records.usualRepsRange, 6...10)
        XCTAssertEqual(records.totalSets, 5)
        XCTAssertTrue(records.hasAnyBest)
    }

    func testHeaviestTieBreaksOnMoreReps() {
        let bench = makeBench()
        let fewerReps = set(bench, daysFromNow: -1, weight: 100, reps: 5)
        let moreReps = set(bench, daysFromNow: 0, weight: 100, reps: 8)

        let records = PersonalRecords.records(for: bench, entries: [fewerReps, moreReps])

        XCTAssertEqual(records.heaviestEntry?.id, moreReps.id)
    }

    func testRecordsForExerciseWithoutHistoryAreEmpty() {
        let bench = makeBench()
        let records = PersonalRecords.records(for: bench, entries: [])

        XCTAssertFalse(records.hasAnyBest)
        XCTAssertNil(records.usualWeightRange)
        XCTAssertNil(records.usualRepsRange)
        XCTAssertEqual(records.totalSets, 0)
    }

    // MARK: - Live projection

    func testProjectedBadgeBeatsExistingRecordOnly() {
        let bench = makeBench()
        let records = PersonalRecords.records(for: bench, entries: [
            set(bench, daysFromNow: -1, weight: 105, reps: 6),
            set(bench, daysFromNow: 0, weight: 100, reps: 10)
        ])

        let heavier = PersonalRecords.projectedBadge(
            storedWeight: 110, weightUnit: .lb, reps: 6,
            beating: records, metrics: .weightAndRepsRequired
        )
        XCTAssertEqual(heavier, [.weight])

        let moreReps = PersonalRecords.projectedBadge(
            storedWeight: 100, weightUnit: .lb, reps: 11,
            beating: records, metrics: .weightAndRepsRequired
        )
        XCTAssertEqual(moreReps, [.reps])

        let neither = PersonalRecords.projectedBadge(
            storedWeight: 100, weightUnit: .lb, reps: 6,
            beating: records, metrics: .weightAndRepsRequired
        )
        XCTAssertTrue(neither.isEmpty)
    }

    func testProjectedBadgeDoesNotFireWithoutPriorRecord() {
        let badge = PersonalRecords.projectedBadge(
            storedWeight: 100, weightUnit: .lb, reps: 5,
            beating: .empty(exerciseID: UUID()), metrics: .weightAndRepsRequired
        )
        XCTAssertTrue(badge.isEmpty)
    }

    // MARK: - Helpers

    private func makeBench() -> Exercise {
        Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    @discardableResult
    private func set(_ exercise: Exercise, daysFromNow: Int, weight: Double?, reps: Int?, unit: WeightUnit = .lb) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: daysFromNow),
            weight: weight,
            weightUnit: unit,
            reps: reps,
            restAfterSeconds: 90
        )
    }

    private func date(daysFromNow: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
