import XCTest
@testable import marble

/// Locks the Progress Top Exercises card ranking: top 5 by lifetime SetEntry
/// count, alphabetical tie-break, lifetime max-weight PB (weight + Trends-style
/// date only, with the year for earlier years).
@MainActor
final class TrendsShareCardTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testRanksByCountAndBreaksTiesAlphabetically() {
        let bench = exercise(named: "Bench Press")
        let squat = exercise(named: "Squat")
        let curl = exercise(named: "Curl")
        // bench x3, squat x3 (tie -> alphabetical: Bench before Squat), curl x1.
        var entries: [SetEntry] = []
        entries += [set(bench, daysFromNow: -3), set(bench, daysFromNow: -2), set(bench, daysFromNow: -1)]
        entries += [set(squat, daysFromNow: -3), set(squat, daysFromNow: -2), set(squat, daysFromNow: -1)]
        entries += [set(curl, daysFromNow: 0)]

        let rows = TrendsShareCard.topExercises(from: entries, now: now)

        XCTAssertEqual(rows.map(\.exerciseName), ["Bench Press", "Squat", "Curl"])
        XCTAssertEqual(rows.count, 3)
    }

    func testCapsAtFiveRows() {
        var entries: [SetEntry] = []
        for i in 0..<7 {
            let ex = exercise(named: "Exercise \(i)")
            for day in 0..<(7 - i) {
                entries.append(set(ex, daysFromNow: -day))
            }
        }

        let rows = TrendsShareCard.topExercises(from: entries, now: now)

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first?.exerciseName, "Exercise 0")
    }

    func testShowsFewerThanFiveWhenLessExists() {
        let bench = exercise(named: "Bench Press")
        let rows = TrendsShareCard.topExercises(from: [set(bench, daysFromNow: 0)], now: now)
        XCTAssertEqual(rows.count, 1)
    }

    func testEmptyEntriesYieldsEmptyRows() {
        let rows = TrendsShareCard.topExercises(from: [], now: now)
        XCTAssertTrue(rows.isEmpty)
    }

    func testPersonalBestIsMaxWeightWithTrendsDateLabelOnly() {
        let bench = exercise(named: "Bench Press")
        let light = set(bench, daysFromNow: -2, weight: 135, reps: 8)
        // Heavier in kilos than 225 lb (~102 kg): PB must be unit-normalized.
        let heavy = set(bench, daysFromNow: 0, weight: 105, reps: 5, unit: .kg)
        let entries = [light, heavy]

        let rows = TrendsShareCard.topExercises(from: entries, now: now)

        XCTAssertEqual(rows.count, 1)
        let best = try? XCTUnwrap(rows.first?.bestSummary)
        XCTAssertTrue(best?.contains("105") == true, "PB is the 105 kg set, got: \(best ?? "nil")")
        XCTAssertTrue(best?.contains("Today") == true, "PB date uses DateHelper.dayLabel, got: \(best ?? "nil")")
        XCTAssertFalse(best?.localizedCaseInsensitiveContains("rep") == true, "PB shows weight + date only, got: \(best ?? "nil")")
        XCTAssertFalse(best?.contains("×") == true, "PB shows weight + date only, got: \(best ?? "nil")")
    }

    func testWeightlessExerciseHasNoBest() {
        let run = Exercise(name: "Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(exercise: run, performedAt: date(daysFromNow: -1), distance: 1000, durationSeconds: 300, restAfterSeconds: 0)

        let rows = TrendsShareCard.topExercises(from: [entry], now: now)

        // No weight PR means this exercise cannot be an overview candidate.
        XCTAssertTrue(rows.isEmpty)
    }

    func testWeightlessRepsExerciseHasNoBest() {
        let pushUp = Exercise(name: "Push-Up", category: .chest, metrics: .repsOnlyRequired, defaultRestSeconds: 60)
        let entry = SetEntry(exercise: pushUp, performedAt: date(daysFromNow: -1), reps: 20, restAfterSeconds: 60)

        let rows = TrendsShareCard.topExercises(from: [entry], now: now)

        // Reps without weight still yield no best: the card shows weight + date only.
        XCTAssertTrue(rows.isEmpty)
    }

    func testIneligibleExercisesDoNotConsumeTopFiveSlots() {
        let missing = exercise(named: "Most Logged Without PR")
        var entries = (0..<10).map { set(missing, daysFromNow: -$0, weight: nil) }
        for i in 0..<6 {
            let eligible = exercise(named: "Eligible \(i)")
            entries += (0..<(6 - i)).map { set(eligible, daysFromNow: -$0) }
        }

        let rows = TrendsShareCard.topExercises(from: entries, now: now)

        XCTAssertEqual(rows.map(\.exerciseName), (0..<5).map { "Eligible \($0)" })
        XCTAssertTrue(rows.allSatisfy { !$0.bestSummary.isEmpty })
        XCTAssertEqual(TrendsShareCard.topExercises(from: entries, limit: 1, now: now).first?.exerciseName, "Eligible 0")
        XCTAssertTrue(TrendsShareCard.topExercises(from: entries, limit: 0, now: now).isEmpty)
        XCTAssertTrue(TrendsShareCard.topExercises(from: entries, limit: -1, now: now).isEmpty)
    }

    func testInvalidPRMetricOrDateIsExcluded() {
        let entries = [
            set(exercise(named: "Zero"), daysFromNow: 0, weight: 0),
            set(exercise(named: "Negative"), daysFromNow: 0, weight: -1),
            set(exercise(named: "Infinite"), daysFromNow: 0, weight: .infinity),
            set(exercise(named: "NaN"), daysFromNow: 0, weight: .nan)
        ]
        let invalidDate = set(exercise(named: "Invalid date"), daysFromNow: 0)
        invalidDate.performedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertTrue(TrendsShareCard.topExercises(from: entries + [invalidDate], now: now).isEmpty)
    }

    func testPRDateComesFromBestSetInsteadOfMostRecentSet() {
        let bench = exercise(named: "Bench")
        let rows = TrendsShareCard.topExercises(from: [
            set(bench, daysFromNow: -1, weight: 200),
            set(bench, daysFromNow: 0, weight: 100)
        ], now: now)
        XCTAssertEqual(rows.first?.bestSummary, "200 lb · Yesterday")
    }

    func testLifetimeTopExercisesRankAndBestFromHistoryOutsideEveryBoundedRange() throws {
        let context = makeInMemoryContext()
        let deadlift = exercise(named: "Deadlift")
        let bench = exercise(named: "Bench Press")
        context.insert(deadlift)
        context.insert(bench)
        let longAgo = date(year: 2023, month: 6, day: 1)
        // Older than the longest bounded range, so a range-scoped query never sees it.
        XCTAssertLessThan(longAgo, try XCTUnwrap(TrendRange.oneYear.startDate))

        for _ in 0..<4 {
            context.insert(set(deadlift, on: longAgo, weight: 405))
        }
        context.insert(set(bench, on: longAgo, weight: 225))
        context.insert(set(bench, daysFromNow: -1, weight: 185))
        context.insert(set(bench, daysFromNow: -1, weight: 185))
        try context.save()

        let rows = TrendsShareCard.lifetimeTopExercises(in: context, now: now)

        // Lifetime counts: Deadlift 4 sets, Bench 3. A 30-day view would show Bench alone at 185.
        XCTAssertEqual(rows.map(\.exerciseName), ["Deadlift", "Bench Press"])
        XCTAssertEqual(rows.map(\.bestSummary), ["405 lb · Jun 1, 2023", "225 lb · Jun 1, 2023"])
    }

    func testBestFromEarlierThisYearKeepsTheDayLabel() {
        let bench = exercise(named: "Bench")
        let rows = TrendsShareCard.topExercises(from: [set(bench, daysFromNow: -13, weight: 200)], now: now)
        XCTAssertEqual(rows.first?.bestSummary, "200 lb · Thu, Jan 2")
    }

    func testBestFromAnEarlierYearShowsTheYear() {
        let bench = exercise(named: "Bench")
        // Only 15 days back, but in the previous year: the weekday label would mislead.
        let rows = TrendsShareCard.topExercises(
            from: [set(bench, on: date(year: 2024, month: 12, day: 31), weight: 200)],
            now: now
        )
        XCTAssertEqual(rows.first?.bestSummary, "200 lb · Dec 31, 2024")
    }

    // MARK: - Helpers

    private func exercise(named name: String) -> Exercise {
        Exercise(name: name, category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func set(
        _ exercise: Exercise,
        daysFromNow: Int,
        weight: Double? = 135,
        reps: Int? = 5,
        unit: WeightUnit = .lb
    ) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: daysFromNow),
            weight: weight,
            weightUnit: unit,
            reps: reps,
            restAfterSeconds: 90
        )
    }

    private func set(_ exercise: Exercise, on day: Date, weight: Double) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: day,
            weight: weight,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)) ?? now
    }

    private func date(daysFromNow: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
