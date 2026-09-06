import XCTest
@testable import marble

/// Locks the Trends shareable card ranking: top 5 by SetEntry count,
/// alphabetical tie-break, max-weight PB (weight + Trends-style date only).
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

    func testEmptyEntriesYieldsEmptyRowsAndEmptyShareText() {
        let rows = TrendsShareCard.topExercises(from: [], now: now)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(TrendsShareCard.shareText(rows: rows), "No exercises logged yet.")
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

        // No logged weight: no usable best, but the row exists and shares "—".
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.bestSummary)
        XCTAssertTrue(rows.first?.shareLine.contains("PB —") == true)
    }

    func testWeightlessRepsExerciseHasNoBest() {
        let pushUp = Exercise(name: "Push-Up", category: .chest, metrics: .repsOnlyRequired, defaultRestSeconds: 60)
        let entry = SetEntry(exercise: pushUp, performedAt: date(daysFromNow: -1), reps: 20, restAfterSeconds: 60)

        let rows = TrendsShareCard.topExercises(from: [entry], now: now)

        // Reps without weight still yield no best: the card shows weight + date only.
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.bestSummary)
        XCTAssertEqual(rows.first?.shareLine, "1. Push-Up — PB —")
    }

    func testShareTextListsRankedLines() {
        let bench = exercise(named: "Bench Press")
        let squat = exercise(named: "Squat")
        let entries = [set(bench, daysFromNow: -1), set(bench, daysFromNow: 0), set(squat, daysFromNow: 0)]

        let text = TrendsShareCard.shareText(rows: TrendsShareCard.topExercises(from: entries, now: now))
        let lines = text.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "My Top Exercises")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("1. Bench Press — PB "), "got: \(lines[1])")
        XCTAssertTrue(lines[2].hasPrefix("2. Squat — PB "), "got: \(lines[2])")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("set"), "share text shows PB only, got:\n\(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("rep"), "share text shows PB only, got:\n\(text)")
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
