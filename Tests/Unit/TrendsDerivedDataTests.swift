import XCTest
@testable import marble

/// Locks the PR-card bests and accessibility summaries that were folded into
/// `TrendsDerivedData.build()` so they are derived once and memoized by the view.
final class TrendsDerivedDataTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func date(daysFromNow: Int, hour: Int, minute: Int) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func testBuildsWeightAndRepsBestsFromFilteredEntries() {
        let exercise = bench()
        let lighter = SetEntry(exercise: exercise, performedAt: date(daysFromNow: -1, hour: 9, minute: 0), weight: 135, weightUnit: .lb, reps: 5, restAfterSeconds: 90)
        let heaviest = SetEntry(exercise: exercise, performedAt: date(daysFromNow: 0, hour: 9, minute: 0), weight: 225, weightUnit: .lb, reps: 3, restAfterSeconds: 90)
        let mostReps = SetEntry(exercise: exercise, performedAt: date(daysFromNow: 0, hour: 9, minute: 30), weight: 95, weightUnit: .lb, reps: 12, restAfterSeconds: 90)

        let derived = TrendsDerivedData.build(
            entries: [mostReps, heaviest, lighter],
            supplementEntries: [],
            historyEntries: [mostReps, heaviest, lighter],
            selectedExercise: nil,
            selectedSupplementType: nil,
            range: .all,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(derived.bestWeightEntry?.weight, 225)
        XCTAssertEqual(derived.bestReps, 12)
        XCTAssertNil(derived.bestDistanceEntry)
        XCTAssertNil(derived.fastestSpeedEntry)
        XCTAssertNil(derived.bestDuration)
    }

    func testBestDistanceAndFastestSpeedComparedInMeters() {
        let run = Exercise(name: "Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        // 100 m @ 20 s = 5.0 m/s
        let shortFast = SetEntry(exercise: run, performedAt: date(daysFromNow: 0, hour: 9, minute: 0), distance: 100, distanceUnit: .meters, durationSeconds: 20, restAfterSeconds: 0)
        // 400 m @ 60 s = 6.67 m/s (fastest)
        let longFastest = SetEntry(exercise: run, performedAt: date(daysFromNow: 0, hour: 10, minute: 0), distance: 400, distanceUnit: .meters, durationSeconds: 60, restAfterSeconds: 0)
        // 500 yd = 457.2 m (farthest) @ 200 s = 2.29 m/s
        let yardsFarthest = SetEntry(exercise: run, performedAt: date(daysFromNow: 0, hour: 11, minute: 0), distance: 500, distanceUnit: .yards, durationSeconds: 200, restAfterSeconds: 0)

        let derived = TrendsDerivedData.build(
            entries: [shortFast, longFastest, yardsFarthest],
            supplementEntries: [],
            historyEntries: [shortFast, longFastest, yardsFarthest],
            selectedExercise: nil,
            selectedSupplementType: nil,
            range: .all,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(derived.bestDistanceEntry?.distance, 500)
        XCTAssertEqual(derived.bestDistanceEntry?.distanceUnit, .yards)
        XCTAssertEqual(derived.fastestSpeedEntry?.distance, 400)
        XCTAssertEqual(derived.bestDuration, 200)
    }

    func testConsistencyAccessibilityValueCountsSetsAndActiveDays() {
        let exercise = bench()
        let entries = [
            SetEntry(exercise: exercise, performedAt: date(daysFromNow: 0, hour: 9, minute: 0), weight: 100, weightUnit: .lb, reps: 5, restAfterSeconds: 90),
            SetEntry(exercise: exercise, performedAt: date(daysFromNow: 0, hour: 9, minute: 20), weight: 100, weightUnit: .lb, reps: 5, restAfterSeconds: 90),
            SetEntry(exercise: exercise, performedAt: date(daysFromNow: -2, hour: 9, minute: 0), weight: 100, weightUnit: .lb, reps: 5, restAfterSeconds: 90)
        ]

        let derived = TrendsDerivedData.build(
            entries: entries,
            supplementEntries: [],
            historyEntries: entries,
            selectedExercise: nil,
            selectedSupplementType: nil,
            range: .thirtyDays,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(derived.consistencyAccessibilityValue, "3 sets over 2 active days")
    }

    /// The Trends queries are now range-scoped at the store (TrendsContentView
    /// builds a `performedAt >= startDate` predicate at init), so `build()`
    /// receives only in-range rows. This pins that a pre-scoped input produces
    /// exactly the same derivation as the old fetch-everything input — i.e.
    /// the query scoping is a pure performance change, not a behavior change.
    func testPreScopedInputMatchesUnscopedDerivation() {
        let exercise = bench()
        var entries: [SetEntry] = []
        // 60 days of history: half inside the 30-day range, half outside.
        for daysAgo in 0..<60 {
            entries.append(SetEntry(
                exercise: exercise,
                performedAt: date(daysFromNow: -daysAgo, hour: 9, minute: 0),
                weight: Double(100 + daysAgo),
                weightUnit: .lb,
                reps: 5,
                restAfterSeconds: 90
            ))
        }

        let cutoff = TrendRange.thirtyDays.startDate
        XCTAssertNotNil(cutoff)
        let scoped = entries.filter { entry in
            cutoff.map { entry.performedAt >= $0 } ?? true
        }
        XCTAssertLessThan(scoped.count, entries.count, "The fixture must actually have out-of-range rows")

        let fromAll = TrendsDerivedData.build(
            entries: entries,
            supplementEntries: [],
            historyEntries: entries,
            selectedExercise: nil,
            selectedSupplementType: nil,
            range: .thirtyDays,
            calendar: calendar,
            now: now
        )
        let fromScoped = TrendsDerivedData.build(
            entries: scoped,
            supplementEntries: [],
            historyEntries: entries,
            selectedExercise: nil,
            selectedSupplementType: nil,
            range: .thirtyDays,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fromScoped.filteredEntries.map(\.id), fromAll.filteredEntries.map(\.id))
        XCTAssertEqual(fromScoped.activeDayCount, fromAll.activeDayCount)
        XCTAssertEqual(fromScoped.consistencySummaries.map(\.count), fromAll.consistencySummaries.map(\.count))
        XCTAssertEqual(fromScoped.weeklySummaries.map(\.weightedVolume), fromAll.weeklySummaries.map(\.weightedVolume))
        XCTAssertEqual(fromScoped.bestWeightEntry?.id, fromAll.bestWeightEntry?.id)
        XCTAssertEqual(fromScoped.bestReps, fromAll.bestReps)
        XCTAssertEqual(fromScoped.consistencyAccessibilityValue, fromAll.consistencyAccessibilityValue)
        XCTAssertEqual(fromScoped.volumeAccessibilityValue, fromAll.volumeAccessibilityValue)
    }
}
