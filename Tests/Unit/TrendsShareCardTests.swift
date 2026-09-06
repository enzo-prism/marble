import XCTest
@testable import marble

/// Locks the Trends shareable card ranking: top 5 by SetEntry count,
/// alphabetical tie-break, max-weight PB with reps + Trends-style date.
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
        XCTAssertEqual(rows.map(\.setCount), [3, 3, 1])
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
        XCTAssertEqual(rows.first?.setCount, 7)
    }

    func testShowsFewerThanFiveWhenLessExists() {
        let bench = exercise(named: "Bench Press")
        let rows = TrendsShareCard.topExercises(from: [set(bench, daysFromNow: 0)], now: now)
        XCTAssertEqual(rows.count, 1)
    }

    func testEmptyEntriesYieldsEmptyRowsAndEmptyShareText() {
        let rows = TrendsShareCard.topExercises(from: [], now: now)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(TrendsShareCard.shareText(rows: rows), "No exercises logged yet.")
    }

    func testPersonalBestIsMaxWeightWithRepsAndTrendsDateLabel() {
        let bench = exercise(named: "Bench Press")
        let light = set(bench, daysFromNow: -2, weight: 135, reps: 8)
        // Heavier in kilos than 225 lb (~102 kg): PB must be unit-normalized.
        let heavy = set(bench, daysFromNow: 0, weight: 105, reps: 5, unit: .kg)
        let entries = [light, heavy]

        let rows = TrendsShareCard.topExercises(from: entries, now: now)

        XCTAssertEqual(rows.count, 1)
        let best = try? XCTUnwrap(rows.first?.bestSummary)
        XCTAssertTrue(best?.contains("105") == true, "PB is the 105 kg set, got: \(best ?? "nil")")
        XCTAssertTrue(best?.contains("5 reps") == true, "PB includes reps, got: \(best ?? "nil")")
        XCTAssertTrue(best?.contains("Today") == true, "PB date uses DateHelper.dayLabel, got: \(best ?? "nil")")
    }

    func testWeightlessExerciseFallsBackToMostRepsBest() {
        let run = Exercise(name: "Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(exercise: run, performedAt: date(daysFromNow: -1), distance: 1000, durationSeconds: 300, restAfterSeconds: 0)

        let rows = TrendsShareCard.topExercises(from: [entry], now: now)

        // No weight or reps on a distance entry: no usable best, but the row exists.
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.bestSummary)
        XCTAssertTrue(rows.first?.shareLine.contains("PB —") == true)
    }

    func testShareTextListsRankedLines() {
        let bench = exercise(named: "Bench Press")
        let squat = exercise(named: "Squat")
        let entries = [set(bench, daysFromNow: -1), set(bench, daysFromNow: 0), set(squat, daysFromNow: 0)]

        let text = TrendsShareCard.shareText(rows: TrendsShareCard.topExercises(from: entries, now: now))
        let lines = text.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "My Top Exercises")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("1. Bench Press — 2 sets · PB "))
        XCTAssertTrue(lines[2].hasPrefix("2. Squat — 1 set · PB "))
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

    private func date(daysFromNow: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
