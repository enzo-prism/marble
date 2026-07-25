import XCTest
@testable import marble

/// Pins the monthly report: totals, the fair same-point-in-month comparison,
/// and the early-month fallback to the last completed month. Fixed test clock
/// is 2025-01-15 (GMT), so the default report is January month-to-date.
@MainActor
final class MonthlyReportTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func set(
        _ exercise: Exercise,
        year: Int,
        month: Int,
        day: Int,
        weight: Double = 100,
        reps: Int = 5,
        hour: Int = 9
    ) -> SetEntry {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        let date = calendar.date(from: components) ?? now
        return SetEntry(exercise: exercise, performedAt: date, weight: weight, weightUnit: .lb, reps: reps, restAfterSeconds: 90)
    }

    private func weighIn(year: Int, month: Int, day: Int, kilograms: Double, hour: Int = 7) -> LifterAnalytics.BodyweightSample {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return LifterAnalytics.BodyweightSample(date: calendar.date(from: components) ?? now, kilograms: kilograms)
    }

    // MARK: - Bodyweight facts

    func testBodyweightFactsReportFirstLastAndDelta() {
        let exercise = bench()
        let history = [3, 8, 13].map { set(exercise, year: 2025, month: 1, day: $0) }
        let weighIns = [
            weighIn(year: 2025, month: 1, day: 2, kilograms: 84),
            weighIn(year: 2025, month: 1, day: 9, kilograms: 83),
            weighIn(year: 2025, month: 1, day: 14, kilograms: 82.5)
        ]

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar, bodyweights: weighIns)

        XCTAssertEqual(report?.bodyweightStartKilograms ?? 0, 84, accuracy: 0.0001)
        XCTAssertEqual(report?.bodyweightEndKilograms ?? 0, 82.5, accuracy: 0.0001)
        XCTAssertEqual(report?.bodyweightDeltaKilograms ?? 0, -1.5, accuracy: 0.0001)
        XCTAssertEqual(report?.bodyweightMeasurements, 3)
    }

    /// A single weigh-in describes a point, not a direction.
    func testSingleWeighInHasNoDelta() {
        let exercise = bench()
        let history = [set(exercise, year: 2025, month: 1, day: 3)]
        let weighIns = [weighIn(year: 2025, month: 1, day: 2, kilograms: 84)]

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar, bodyweights: weighIns)

        XCTAssertEqual(report?.bodyweightEndKilograms ?? 0, 84, accuracy: 0.0001)
        XCTAssertNil(report?.bodyweightDeltaKilograms)
        XCTAssertEqual(report?.bodyweightMeasurements, 1)
    }

    func testNoWeighInsMeansNoBodyweightFacts() {
        let exercise = bench()
        let history = [set(exercise, year: 2025, month: 1, day: 3)]

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)

        XCTAssertNil(report?.bodyweightStartKilograms)
        XCTAssertNil(report?.bodyweightEndKilograms)
        XCTAssertNil(report?.bodyweightDeltaKilograms)
        XCTAssertEqual(report?.bodyweightMeasurements, 0)
    }

    /// Month-to-date clips at "now" for the same reason the session deltas do —
    /// a half-finished month must not borrow a future weigh-in.
    func testMonthToDateIgnoresWeighInsAfterNow() {
        let exercise = bench()
        let history = [set(exercise, year: 2025, month: 1, day: 3)]
        let weighIns = [
            weighIn(year: 2025, month: 1, day: 2, kilograms: 84),
            weighIn(year: 2025, month: 1, day: 28, kilograms: 80)
        ]

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar, bodyweights: weighIns)

        XCTAssertEqual(report?.isMonthToDate, true)
        XCTAssertEqual(report?.bodyweightMeasurements, 1)
        XCTAssertEqual(report?.bodyweightEndKilograms ?? 0, 84, accuracy: 0.0001)
    }

    /// Weigh-ins outside the reported month never leak in — the early-month
    /// fallback reports December, so only December's weigh-ins count.
    func testCompletedMonthReportUsesThatMonthsWeighIns() {
        let exercise = bench()
        var history: [SetEntry] = []
        for day in [5, 10, 20] { history.append(set(exercise, year: 2024, month: 12, day: day)) }
        let earlyJanuary = calendar.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 9)) ?? now
        let weighIns = [
            weighIn(year: 2024, month: 12, day: 4, kilograms: 86),
            weighIn(year: 2024, month: 12, day: 27, kilograms: 84),
            weighIn(year: 2025, month: 1, day: 1, kilograms: 90)
        ]

        let report = MonthlyReportBuilder.build(history: history, now: earlyJanuary, calendar: calendar, bodyweights: weighIns)

        XCTAssertEqual(report?.isMonthToDate, false)
        XCTAssertEqual(report?.bodyweightMeasurements, 2)
        XCTAssertEqual(report?.bodyweightStartKilograms ?? 0, 86, accuracy: 0.0001)
        XCTAssertEqual(report?.bodyweightEndKilograms ?? 0, 84, accuracy: 0.0001)
    }

    func testMonthToDateComparesAgainstSamePointLastMonth() {
        let exercise = bench()
        var history: [SetEntry] = []
        // January (through the 15th): 3 sessions.
        for day in [3, 8, 13] { history.append(set(exercise, year: 2025, month: 1, day: day)) }
        // December: 2 sessions before the 16th, 3 after — the late ones must
        // NOT count against a mid-month January.
        for day in [5, 10, 20, 24, 28] { history.append(set(exercise, year: 2024, month: 12, day: day)) }

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)

        XCTAssertEqual(report?.isMonthToDate, true)
        XCTAssertEqual(report?.sessions, 3)
        XCTAssertEqual(report?.sessionsDelta, 1, "3 January sessions vs 2 December sessions through the 15th")
        XCTAssertEqual(report?.comparisonLabel, "vs this point in December")
    }

    func testEarlyMonthFallsBackToCompletedMonth() {
        let exercise = bench()
        var history: [SetEntry] = []
        for day in [5, 10, 20] { history.append(set(exercise, year: 2024, month: 12, day: day)) }

        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 3
        components.hour = 12
        let earlyJanuary = calendar.date(from: components)!

        let report = MonthlyReportBuilder.build(history: history, now: earlyJanuary, calendar: calendar)

        XCTAssertEqual(report?.isMonthToDate, false)
        XCTAssertEqual(report?.monthLabel, "December 2024")
        XCTAssertEqual(report?.sessions, 3)
    }

    func testVolumeIsKilogramNormalized() {
        let exercise = bench()
        let history = [
            set(exercise, year: 2025, month: 1, day: 10, weight: 100, reps: 10)
        ]

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)

        // 100 lb × 10 reps = 1000 lb·reps ≈ 453.6 kg·reps.
        XCTAssertEqual(report?.volumeKilograms ?? 0, 453.59237, accuracy: 0.001)
    }

    func testPRCountUsesFeedRules() {
        let exercise = bench()
        // Five rising sessions in January: the feed suppresses the baseline
        // and first three sessions, leaving two genuine record days.
        let history = (0..<5).map { index in
            set(exercise, year: 2025, month: 1, day: 2 + index * 3, weight: 100 + Double(index) * 10)
        }

        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)

        XCTAssertEqual(report?.prCount, 2)
    }

    func testNoDataReturnsNil() {
        XCTAssertNil(MonthlyReportBuilder.build(history: [], now: now, calendar: calendar))
    }

    func testPrecomputedPREventsProduceEquivalentReport() {
        let exercise = bench()
        let history = (0..<8).map { index in
            let isPreviousMonth = index < 4
            return set(
                exercise,
                year: isPreviousMonth ? 2024 : 2025,
                month: isPreviousMonth ? 12 : 1,
                day: (index % 4) * 3 + 2,
                weight: 100 + Double(index) * 5
            )
        }
        let events = LifterCoaching.prEvents(
            history: history,
            rangeStart: nil,
            selectedExerciseID: nil,
            calendar: calendar
        )

        let direct = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)
        let reused = MonthlyReportBuilder.build(
            history: history,
            now: now,
            calendar: calendar,
            precomputedPREvents: events
        )

        XCTAssertEqual(reused, direct)
    }

    func testFallbackInsightsAlwaysGrounded() {
        let exercise = bench()
        let history = [set(exercise, year: 2025, month: 1, day: 10)]
        let report = MonthlyReportBuilder.build(history: history, now: now, calendar: calendar)!

        let insights = MonthlyReportPhrasing.fallbackInsights(for: report)

        XCTAssertFalse(insights.isEmpty)
        XCTAssertLessThanOrEqual(insights.count, 3)
    }
}
