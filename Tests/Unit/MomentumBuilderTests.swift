import XCTest
@testable import marble

final class MomentumBuilderTests: MarbleTestCase {
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

    func testSetsDeltaIsUpWhenCurrentWindowExceedsPrevious() {
        let exercise = makeExercise()
        // Current 7-day window (Jan 9–15): three sessions. Previous window (Jan 2–8): one.
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -1, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -2, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -8, weight: 100, reps: 5)
        ]

        let summary = MomentumBuilder.build(entries: entries, range: .sevenDays, exercise: exercise, now: now, calendar: calendar)
        let sets = summary.deltas.first { $0.title == "Sets" }

        XCTAssertEqual(sets?.valueText, "3")
        XCTAssertEqual(sets?.direction, .up)
        XCTAssertEqual(sets?.changeText, "200%")
        XCTAssertTrue(summary.hasContent)
    }

    func testDeltaIsNewWhenPreviousWindowEmpty() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -1, weight: 100, reps: 5)
        ]

        let summary = MomentumBuilder.build(entries: entries, range: .sevenDays, exercise: exercise, now: now, calendar: calendar)
        let sets = summary.deltas.first { $0.title == "Sets" }

        XCTAssertEqual(sets?.changeText, "New")
        XCTAssertEqual(sets?.direction, .up)
    }

    func testAllRangeHasNoDeltas() {
        let exercise = makeExercise()
        let entries = [entry(exercise, daysFromNow: 0, weight: 100, reps: 5)]

        let summary = MomentumBuilder.build(entries: entries, range: .all, exercise: exercise, now: now, calendar: calendar)

        XCTAssertTrue(summary.deltas.isEmpty)
    }

    func testStreakCountsConsecutiveActiveWeeks() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),   // this week
            entry(exercise, daysFromNow: -7, weight: 100, reps: 5),  // last week
            entry(exercise, daysFromNow: -14, weight: 100, reps: 5)  // two weeks ago
        ]

        let streak = MomentumBuilder.streakWeeks(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(streak, 3)
    }

    func testStreakSurvivesEmptyInProgressWeek() {
        let exercise = makeExercise()
        // Nothing logged in the current week yet, but the two prior weeks were active.
        let entries = [
            entry(exercise, daysFromNow: -7, weight: 100, reps: 5),
            entry(exercise, daysFromNow: -14, weight: 100, reps: 5)
        ]

        let streak = MomentumBuilder.streakWeeks(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(streak, 2)
    }

    func testStreakBreaksOnGap() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: 0, weight: 100, reps: 5),    // this week
            entry(exercise, daysFromNow: -21, weight: 100, reps: 5)   // three weeks ago (gap between)
        ]

        let streak = MomentumBuilder.streakWeeks(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(streak, 1)
    }

    func testRecentPRDetectsHeaviestWithinWindow() {
        let exercise = makeExercise()
        let entries = [
            entry(exercise, daysFromNow: -2, weight: 200, reps: 2),   // all-time heaviest, recent
            entry(exercise, daysFromNow: -20, weight: 180, reps: 5)
        ]

        let pr = MomentumBuilder.recentPR(entries: entries, now: now, calendar: calendar)

        XCTAssertEqual(pr?.metricTitle, "Heaviest")
        XCTAssertEqual(pr?.valueText, "200 lb")
        XCTAssertEqual(pr?.exerciseName, "Bench Press")
    }

    func testNoRecentPRWhenRecordPredatesWindow() {
        let exercise = makeExercise()
        // The old entry holds every record; the recent entry is worse on weight and reps,
        // so nothing new was set inside the window.
        let entries = [
            entry(exercise, daysFromNow: -20, weight: 200, reps: 5),
            entry(exercise, daysFromNow: -2, weight: 150, reps: 3)
        ]

        let pr = MomentumBuilder.recentPR(entries: entries, now: now, calendar: calendar)
        XCTAssertNil(pr)
    }
}
