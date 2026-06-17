import XCTest
@testable import marble

final class StreakBuilderTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func makeExercise() -> Exercise {
        Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    /// A logged set on the day `daysFromNow` away from the fixed `now` (negatives are the past).
    private func entry(_ exercise: Exercise, daysFromNow: Int, hour: Int = 9) -> SetEntry {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        let performedAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: 100,
            weightUnit: .lb,
            reps: 5,
            difficulty: 8,
            restAfterSeconds: 90
        )
    }

    // MARK: - Empty / no history

    func testEmptyEntriesYieldEmptySummary() {
        let summary = StreakBuilder.build(entries: [], now: now, calendar: calendar)
        XCTAssertEqual(summary, .empty)
        XCTAssertFalse(summary.hasHistory)
        XCTAssertFalse(summary.loggedToday)
    }

    // MARK: - Current streak

    func testSingleSetTodayIsAOneDayStreak() {
        let exercise = makeExercise()
        let summary = StreakBuilder.build(entries: [entry(exercise, daysFromNow: 0)], now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 1)
        XCTAssertEqual(summary.best, 1)
        XCTAssertTrue(summary.loggedToday)
        XCTAssertTrue(summary.hasHistory)
    }

    func testConsecutiveDaysEndingTodayCount() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0),
            entry(exercise, daysFromNow: -1),
            entry(exercise, daysFromNow: -2),
            entry(exercise, daysFromNow: -3)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 4)
        XCTAssertEqual(summary.best, 4)
        XCTAssertTrue(summary.loggedToday)
    }

    func testUnloggedTodayKeepsStreakAliveFromYesterday() {
        let exercise = makeExercise()
        // Nothing logged today yet, but the three prior days were active. The user still
        // has until midnight, so the streak counts (3) and is anchored at yesterday.
        let entries = [
            entry(exercise, daysFromNow: -1),
            entry(exercise, daysFromNow: -2),
            entry(exercise, daysFromNow: -3)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 3)
        XCTAssertEqual(summary.best, 3)
        XCTAssertFalse(summary.loggedToday)
    }

    func testMissingTodayAndYesterdayBreaksCurrentStreak() {
        let exercise = makeExercise()
        // The most recent activity was two days ago, so the streak has lapsed.
        let entries = [
            entry(exercise, daysFromNow: -2),
            entry(exercise, daysFromNow: -3),
            entry(exercise, daysFromNow: -4)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 0)
        XCTAssertEqual(summary.best, 3)
        XCTAssertFalse(summary.loggedToday)
    }

    func testGapResetsCurrentStreakToTrailingRun() {
        let exercise = makeExercise()
        // Active today and yesterday, then a one-day gap (-2 missing), then an older block.
        let entries = [
            entry(exercise, daysFromNow: 0),
            entry(exercise, daysFromNow: -1),
            entry(exercise, daysFromNow: -3),
            entry(exercise, daysFromNow: -4)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 2)
    }

    // MARK: - Best streak

    func testBestStreakReflectsLongestPastRun() {
        let exercise = makeExercise()
        // Current run is 2 days (today, -1). An older run of 4 days (-5…-8) is the all-time best.
        let entries = [
            entry(exercise, daysFromNow: 0),
            entry(exercise, daysFromNow: -1),
            entry(exercise, daysFromNow: -5),
            entry(exercise, daysFromNow: -6),
            entry(exercise, daysFromNow: -7),
            entry(exercise, daysFromNow: -8)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.best, 4)
    }

    func testBestNeverFallsBelowCurrent() {
        let exercise = makeExercise()
        let entries = (0...5).map { entry(exercise, daysFromNow: -$0) }
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertGreaterThanOrEqual(summary.best, summary.current)
        XCTAssertEqual(summary.current, 6)
        XCTAssertEqual(summary.best, 6)
    }

    // MARK: - De-duplication

    func testMultipleSetsOnSameDayCountAsOneStreakDay() {
        let exercise = makeExercise()
        // Five sets across two days should be a 2-day streak, not five.
        let entries = [
            entry(exercise, daysFromNow: 0, hour: 8),
            entry(exercise, daysFromNow: 0, hour: 12),
            entry(exercise, daysFromNow: 0, hour: 18),
            entry(exercise, daysFromNow: -1, hour: 7),
            entry(exercise, daysFromNow: -1, hour: 20)
        ]
        let summary = StreakBuilder.build(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.best, 2)
    }

    // MARK: - currentStreak convenience

    func testCurrentStreakConvenienceMatchesBuild() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0),
            entry(exercise, daysFromNow: -1),
            entry(exercise, daysFromNow: -2)
        ]
        let current = StreakBuilder.currentStreak(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(current, 3)
        XCTAssertEqual(current, StreakBuilder.build(entries: entries, now: now, calendar: calendar).current)
    }
}
