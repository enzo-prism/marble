import XCTest
@testable import marble

final class LifterAnalyticsTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func date(daysFromNow: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func set(
        _ exercise: Exercise,
        daysAgo: Int,
        hour: Int = 9,
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        difficulty: Int = 8
    ) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: -daysAgo, hour: hour),
            weight: weight,
            weightUnit: unit,
            reps: reps,
            difficulty: difficulty,
            restAfterSeconds: 90
        )
    }

    // MARK: - Epley estimate

    func testEpleyEstimateMatchesFormulaAndNormalizesUnits() {
        // 100 kg × 5 → 100 × (1 + 5/30) = 116.67 kg
        let fromKg = LifterAnalytics.estimatedOneRepMaxKilograms(weight: 100, unit: .kg, reps: 5)
        XCTAssertEqual(fromKg ?? 0, 116.666, accuracy: 0.01)

        // 225 lb × 5 → 102.06 kg × 1.1667 = 119.07 kg
        let fromLb = LifterAnalytics.estimatedOneRepMaxKilograms(weight: 225, unit: .lb, reps: 5)
        XCTAssertEqual(fromLb ?? 0, 119.073, accuracy: 0.01)

        // A single is its own max.
        XCTAssertEqual(
            LifterAnalytics.estimatedOneRepMaxKilograms(weight: 100, unit: .kg, reps: 1) ?? 0,
            103.333,
            accuracy: 0.01
        )
    }

    func testEpleyEstimateRejectsInvalidInputs() {
        // The formulas fall apart past ~12 reps; the majors cut off rather than clamp.
        XCTAssertNil(LifterAnalytics.estimatedOneRepMaxKilograms(weight: 100, unit: .kg, reps: 13))
        XCTAssertNil(LifterAnalytics.estimatedOneRepMaxKilograms(weight: 100, unit: .kg, reps: 0))
        XCTAssertNil(LifterAnalytics.estimatedOneRepMaxKilograms(weight: 0, unit: .kg, reps: 5))
        XCTAssertNotNil(LifterAnalytics.estimatedOneRepMaxKilograms(weight: 100, unit: .kg, reps: 12))
    }

    // MARK: - e1RM series

    func testSeriesPicksBestSetPerDayAcrossUnits() {
        let exercise = bench()
        let entries = [
            // Day -1: 100 kg × 5 (e1RM 116.7 kg) beats 200 lb × 5 (105.8 kg).
            set(exercise, daysAgo: 1, hour: 9, weight: 200, unit: .lb, reps: 5),
            set(exercise, daysAgo: 1, hour: 10, weight: 100, unit: .kg, reps: 5),
            // Day 0: lighter day; most recent set is in lb → display unit lb.
            set(exercise, daysAgo: 0, hour: 9, weight: 185, unit: .lb, reps: 8)
        ]

        let series = LifterAnalytics.oneRepMaxSeries(entries: entries, exercise: exercise, calendar: calendar)

        XCTAssertEqual(series?.points.count, 2)
        XCTAssertEqual(series?.displayUnit, .lb)
        XCTAssertEqual(series?.points.first?.kilograms ?? 0, 116.666, accuracy: 0.01)
        XCTAssertEqual(series?.points.first?.bestSetSummary, "100 kg \u{00D7} 5")
        // Best overall is day -1's kg set.
        XCTAssertEqual(series?.best?.kilograms ?? 0, 116.666, accuracy: 0.01)
        // Display value converts kg → lb.
        XCTAssertEqual(series?.best?.displayValue ?? 0, 257.2, accuracy: 0.1)
    }

    func testSeriesExcludesHighRepSetsAndForeignExercises() {
        let exercise = bench()
        let curls = Exercise(name: "Curl", category: .biceps, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        let entries = [
            set(exercise, daysAgo: 0, hour: 9, weight: 135, unit: .lb, reps: 20),
            set(curls, daysAgo: 0, hour: 10, weight: 60, unit: .lb, reps: 8)
        ]

        XCTAssertNil(LifterAnalytics.oneRepMaxSeries(entries: entries, exercise: exercise, calendar: calendar))
    }

    func testSeriesRequiresWeightAndRepsMetrics() {
        let plank = Exercise(name: "Plank", category: .core, metrics: .durationOnlyRequired, defaultRestSeconds: 45)
        XCTAssertNil(LifterAnalytics.oneRepMaxSeries(entries: [], exercise: plank, calendar: calendar))
    }

    // MARK: - Muscle group sets

    func testMuscleGroupSetsCountsAndSortsMuscleCategoriesOnly() {
        let benchPress = bench()
        let squat = Exercise(name: "Squat", category: .quads, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let run = Exercise(name: "Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entries = [
            set(benchPress, daysAgo: 0, hour: 9, weight: 185, reps: 5),
            set(benchPress, daysAgo: 0, hour: 10, weight: 185, reps: 5),
            set(squat, daysAgo: 1, hour: 9, weight: 225, reps: 5),
            set(run, daysAgo: 2, hour: 9)
        ]

        let groups = LifterAnalytics.muscleGroupSets(entries: entries, weekCount: nil)

        XCTAssertEqual(groups.map(\.category), [.chest, .quads])
        XCTAssertEqual(groups.map(\.setCount), [2, 1])
        XCTAssertTrue(groups.allSatisfy { $0.averagePerWeek == nil })
    }

    func testMuscleGroupWeeklyAverageNeedsTwoWeeks() {
        let exercise = bench()
        let entries = [set(exercise, daysAgo: 0, weight: 185, reps: 5)]

        let short = LifterAnalytics.muscleGroupSets(entries: entries, weekCount: 1.0)
        XCTAssertNil(short.first?.averagePerWeek)

        let month = LifterAnalytics.muscleGroupSets(entries: entries, weekCount: 4.0)
        XCTAssertEqual(month.first?.averagePerWeek ?? 0, 0.25, accuracy: 0.001)
    }

    func testWeekCountFromRangeAndFromHistory() {
        // Ranged: ~30 days ≈ 4.3 weeks.
        let thirty = LifterAnalytics.weekCount(range: .thirtyDays, entries: [], now: now)
        XCTAssertEqual(thirty ?? 0, 29.0 / 7.0, accuracy: 0.2)

        // All-time: span from the earliest entry.
        let exercise = bench()
        let entries = [set(exercise, daysAgo: 28, weight: 185, reps: 5)]
        let all = LifterAnalytics.weekCount(range: .all, entries: entries, now: now)
        XCTAssertEqual(all ?? 0, 4.0, accuracy: 0.2)

        // All-time with no entries has no span.
        XCTAssertNil(LifterAnalytics.weekCount(range: .all, entries: [], now: now))
    }

    // MARK: - Rep ranges

    func testRepRangeDistributionBucketsAndShares() {
        let exercise = bench()
        let entries = [
            set(exercise, daysAgo: 0, hour: 8, weight: 225, reps: 3),
            set(exercise, daysAgo: 0, hour: 9, weight: 185, reps: 8),
            set(exercise, daysAgo: 0, hour: 10, weight: 185, reps: 10),
            set(exercise, daysAgo: 0, hour: 11, weight: 95, reps: 15)
        ]

        let buckets = LifterAnalytics.repRangeDistribution(entries: entries)

        XCTAssertEqual(buckets.map(\.kind), [.strength, .hypertrophy, .endurance])
        XCTAssertEqual(buckets.map(\.setCount), [1, 2, 1])
        XCTAssertEqual(buckets[1].share, 0.5, accuracy: 0.001)
    }

    func testRepRangeDistributionEmptyWithoutReps() {
        let plank = Exercise(name: "Plank", category: .core, metrics: .durationOnlyRequired, defaultRestSeconds: 45)
        let entries = [set(plank, daysAgo: 0)]
        XCTAssertTrue(LifterAnalytics.repRangeDistribution(entries: entries).isEmpty)
    }
}
