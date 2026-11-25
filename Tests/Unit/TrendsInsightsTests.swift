import XCTest
@testable import marble

/// Pins the inputs behind the redesigned Progress Details visuals: the Pulse
/// card's period-over-period deltas and the consistency heatmap.
@MainActor
final class TrendsInsightsTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func day(_ daysFromNow: Int) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
    }

    private func set(_ exercise: Exercise, daysFromNow: Int, weight: Double = 100, unit: WeightUnit = .kg, reps: Int = 5) -> SetEntry {
        let performedAt = calendar.date(byAdding: .hour, value: 9, to: day(daysFromNow)) ?? day(daysFromNow)
        return SetEntry(exercise: exercise, performedAt: performedAt, weight: weight, weightUnit: unit, reps: reps, restAfterSeconds: 90)
    }

    // MARK: Period comparison

    func testComparisonUsesTheEqualLengthWindowBeforeTheRange() throws {
        let exercise = bench()
        let rangeStart = day(-6) // a 7-day range: today and the six days before
        let current = [set(exercise, daysFromNow: 0), set(exercise, daysFromNow: -6), set(exercise, daysFromNow: -6)]
        let previous = [set(exercise, daysFromNow: -7), set(exercise, daysFromNow: -13)]
        let tooOld = set(exercise, daysFromNow: -14)

        let comparison = try XCTUnwrap(TrendsPeriodComparison.make(
            history: current + previous + [tooOld],
            currentEntries: current,
            selectedExerciseID: nil,
            rangeStart: rangeStart,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(comparison.currentSets, 3)
        XCTAssertEqual(comparison.previousSets, 2, "day -14 sits outside the previous 7-day window")
        XCTAssertEqual(comparison.currentActiveDays, 2)
        XCTAssertEqual(comparison.previousActiveDays, 2)
        XCTAssertEqual(try XCTUnwrap(comparison.setsChangePercent), 50, accuracy: 0.001)
    }

    func testComparisonNormalizesVolumeToKilograms() throws {
        let exercise = bench()
        // 500 kg now vs the same 500 kg logged in pounds before: flat, not +120%.
        let current = [set(exercise, daysFromNow: 0, weight: 100, unit: .kg, reps: 5)]
        let previous = [set(exercise, daysFromNow: -8, weight: 220.46226218487757, unit: .lb, reps: 5)]

        let comparison = try XCTUnwrap(TrendsPeriodComparison.make(
            history: current + previous,
            currentEntries: current,
            selectedExerciseID: nil,
            rangeStart: day(-6),
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(comparison.currentVolumeKilograms, 500, accuracy: 0.01)
        XCTAssertEqual(comparison.previousVolumeKilograms, 500, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(comparison.volumeChangePercent), 0, accuracy: 0.01)
    }

    func testComparisonHonorsTheSelectedExercise() throws {
        let benchPress = bench()
        let squat = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let current = [set(benchPress, daysFromNow: 0)]
        let history = current + [set(benchPress, daysFromNow: -8), set(squat, daysFromNow: -8), set(squat, daysFromNow: -9)]

        let comparison = try XCTUnwrap(TrendsPeriodComparison.make(
            history: history,
            currentEntries: current,
            selectedExerciseID: benchPress.id,
            rangeStart: day(-6),
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(comparison.previousSets, 1)
    }

    func testComparisonIsNilForAllTimeAndPercentIsNilWithoutHistory() throws {
        let exercise = bench()
        let current = [set(exercise, daysFromNow: 0)]
        XCTAssertNil(TrendsPeriodComparison.make(
            history: current, currentEntries: current, selectedExerciseID: nil,
            rangeStart: nil, now: now, calendar: calendar
        ))

        let firstWeek = try XCTUnwrap(TrendsPeriodComparison.make(
            history: current, currentEntries: current, selectedExerciseID: nil,
            rangeStart: day(-6), now: now, calendar: calendar
        ))
        XCTAssertNil(firstWeek.setsChangePercent, "no previous sets means no percentage, not +∞")
    }

    // MARK: Heatmap

    func testHeatmapCoversEveryDayOfTheRangeAndEndsToday() {
        let model = TrendsHeatmapModel.make(
            dayCounts: [day(-2): 3],
            prDays: [],
            rangeStart: day(-29),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(model.days.count, 30)
        XCTAssertEqual(model.first, day(-29))
        XCTAssertEqual(model.last, day(0))
        XCTAssertTrue(model.days.last?.isToday == true)
        XCTAssertEqual(model.days.filter(\.isToday).count, 1)
    }

    func testHeatmapLevelsAreQuartilesOfTheBusiestDay() {
        XCTAssertEqual(TrendsHeatmapModel.level(count: 0, maxCount: 8), 0)
        XCTAssertEqual(TrendsHeatmapModel.level(count: 1, maxCount: 8), 1)
        XCTAssertEqual(TrendsHeatmapModel.level(count: 2, maxCount: 8), 1)
        XCTAssertEqual(TrendsHeatmapModel.level(count: 3, maxCount: 8), 2)
        XCTAssertEqual(TrendsHeatmapModel.level(count: 6, maxCount: 8), 3)
        XCTAssertEqual(TrendsHeatmapModel.level(count: 8, maxCount: 8), 4)
    }

    func testHeatmapStreaksForgiveARestDayToday() {
        // Trained -5…-3 (3 days), rested -2, trained -1, resting today.
        let counts: [Date: Int] = [day(-5): 2, day(-4): 1, day(-3): 4, day(-1): 2]
        let model = TrendsHeatmapModel.make(
            dayCounts: counts,
            prDays: [day(-3)],
            rangeStart: day(-6),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(model.activeDays, 4)
        XCTAssertEqual(model.longestStreak, 3)
        XCTAssertEqual(model.currentStreak, 1, "today's rest doesn't break yesterday's streak")
        XCTAssertEqual(model.maxCount, 4)
        XCTAssertEqual(model.day(for: day(-3), calendar: calendar)?.hasPR, true)
        XCTAssertEqual(model.day(for: day(-3), calendar: calendar)?.level, 4)
    }

    func testHeatmapBusiestWeekdayPrefersMostActiveDays() throws {
        // Two sessions on the weekday of day(-7) (same weekday as today), one elsewhere.
        let counts: [Date: Int] = [day(-7): 1, day(-14): 1, day(-3): 5]
        let model = TrendsHeatmapModel.make(
            dayCounts: counts,
            prDays: [],
            rangeStart: day(-20),
            now: now,
            calendar: calendar
        )
        let expected = calendar.component(.weekday, from: day(-7))
        XCTAssertEqual(model.busiestWeekday, expected, "counts days trained, not sets logged")
    }

    func testAllTimeHeatmapIsCappedButStartsAtTheFirstLog() {
        let recent = TrendsHeatmapModel.make(
            dayCounts: [day(-10): 1],
            prDays: [],
            rangeStart: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(recent.days.count, 11)

        let ancient = TrendsHeatmapModel.make(
            dayCounts: [day(-1000): 1, day(-1): 1],
            prDays: [],
            rangeStart: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(ancient.days.count, 371)
        XCTAssertEqual(ancient.activeDays, 1)
    }

    // MARK: Geometry

    func testHeatmapGeometryPicksALayoutForTheSpan() {
        XCTAssertEqual(TrendsHeatmapGeometry.style(forDayCount: 7), .strip)
        XCTAssertEqual(TrendsHeatmapGeometry.style(forDayCount: 30), .calendar)
        XCTAssertEqual(TrendsHeatmapGeometry.style(forDayCount: 90), .contribution)
        XCTAssertEqual(TrendsHeatmapGeometry.style(forDayCount: 366), .months)
    }

    func testHeatmapGeometryMapsEveryVisibleDayBackFromItsCenter() {
        for span in [7, 30, 90, 366] {
            let days = (0..<span).map { day(-(span - 1) + $0) }
            let geometry = TrendsHeatmapGeometry(days: days, width: 311, labelHeight: 13, calendar: calendar)
            XCTAssertLessThanOrEqual(geometry.size.width, 311.5, "span \(span) overflows")
            for (index, rect) in geometry.cellRects.enumerated() where rect.width > 0 {
                XCTAssertGreaterThanOrEqual(rect.minX, -0.5, "span \(span) day \(index) starts off-canvas")
                XCTAssertLessThanOrEqual(rect.maxX, geometry.size.width + 0.5, "span \(span) day \(index) overflows")
                XCTAssertEqual(
                    geometry.dayIndex(at: CGPoint(x: rect.midX, y: rect.midY)),
                    index,
                    "span \(span): tapping day \(index) selects another day"
                )
            }
        }
    }
}
