import SwiftData
import XCTest
@testable import marble

/// Correctness tripwires for the scoped Daily Highlights fetch.
///
/// `DailyHighlightQueries.history(for:in:)` replaced a full-table `SetEntry`
/// fetch, so the contract under test is equivalence: the scoped projection
/// must be indistinguishable to `DailyHighlightsBuilder` from the whole table
/// — identical summary, including the all-time record baseline — while never
/// containing rows the builder cannot consume (other exercises' prior
/// history, entries after the celebration day).
final class DailyHighlightQueriesTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testScopedHistoryDerivesIdenticalSummaryToFullTable() throws {
        let context = makeInMemoryContext()
        let bench = exercise(named: "Bench Press")
        let squat = exercise(named: "Squat")
        let deadlift = exercise(named: "Deadlift")
        [bench, squat, deadlift].forEach(context.insert)

        // Bench: an all-time best two *years* back must veto today's heavier-
        // than-last-week set. This is exactly the case a date-margin cutoff
        // would get wrong, so it anchors the "scope by exercise, not by date"
        // choice. Today's set still qualifies as lift progress vs last session.
        insertEntry(context, bench, dayOffset: -730, hour: 10, weight: 315, reps: 5)
        insertEntry(context, bench, dayOffset: -3, hour: 10, weight: 185, reps: 5)
        insertEntry(context, bench, dayOffset: 0, hour: 18, weight: 225, reps: 5)
        // Squat: a genuine same-day weight record.
        insertEntry(context, squat, dayOffset: -5, hour: 10, weight: 200, reps: 5)
        insertEntry(context, squat, dayOffset: 0, hour: 18, weight: 225, reps: 5, minute: 30)
        // A same-day row after the builder's 21:00 cutoff: both scoped and
        // full paths must include-then-ignore it identically.
        insertEntry(context, squat, dayOffset: 0, hour: 23, weight: 500, reps: 5)
        // Deadlift was not trained today: its prior history is grouped but
        // never looked up by the builder, so the scoped fetch omits it.
        insertEntry(context, deadlift, dayOffset: -10, hour: 10, weight: 405, reps: 3)
        // A future-day row is outside the builder's day bounds entirely.
        insertEntry(context, bench, dayOffset: 1, hour: 10, weight: 230, reps: 5)
        try context.save()

        let occurrence = try defaultOccurrence()
        let scoped = DailyHighlightQueries.history(for: occurrence, in: context, calendar: calendar)
        let full = try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt)]))

        let fromScoped = build(history: scoped, occurrence: occurrence)
        let fromFull = build(history: full, occurrence: occurrence)

        XCTAssertEqual(fromScoped, fromFull)
        let summary = try XCTUnwrap(fromScoped)
        XCTAssertEqual(summary.personalRecordCount, 1)
        XCTAssertEqual(summary.achievements.first?.kind, .personalRecord)
        XCTAssertEqual(summary.achievements.first?.title, "Squat")
        XCTAssertTrue(summary.achievements.contains { $0.kind == .liftProgress && $0.title == "Bench Press" })

        // Scope: today's exercises (all their history, all of today) and
        // nothing else — 3 bench + 3 squat rows, no deadlift, nothing future.
        XCTAssertEqual(scoped.count, 6)
        XCTAssertFalse(scoped.contains { $0.exercise.id == deadlift.id })
        let dayEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: occurrence.celebrationDay))
        XCTAssertFalse(scoped.contains { $0.performedAt >= dayEnd })
    }

    func testScopedHistoryIsEmptyWhenNothingLoggedOnCelebrationDay() throws {
        let context = makeInMemoryContext()
        let bench = exercise(named: "Bench Press")
        context.insert(bench)
        insertEntry(context, bench, dayOffset: -2, hour: 10, weight: 185, reps: 5)
        try context.save()

        let occurrence = try defaultOccurrence()
        let scoped = DailyHighlightQueries.history(for: occurrence, in: context, calendar: calendar)
        let full = try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt)]))

        // Prior-only history: the builder hides the card either way, so the
        // scoped fetch may (and should) skip the prior fetch entirely.
        XCTAssertTrue(scoped.isEmpty)
        XCTAssertNil(build(history: scoped, occurrence: occurrence))
        XCTAssertNil(build(history: full, occurrence: occurrence))
    }

    // MARK: - Helpers

    private func defaultOccurrence() throws -> DailyHighlightOccurrence {
        try XCTUnwrap(DailyHighlightWindow(
            startMinute: DailyHighlightWindow.defaultStartMinute,
            endMinute: DailyHighlightWindow.defaultEndMinute
        ).occurrence(containing: date(dayOffset: 0, hour: 21, minute: 0), calendar: calendar))
    }

    private func build(
        history: [SetEntry],
        occurrence: DailyHighlightOccurrence
    ) -> DailyHighlightSummary? {
        DailyHighlightsBuilder.build(
            history: history,
            occurrence: occurrence,
            now: date(dayOffset: 0, hour: 21, minute: 0),
            displayWeightUnit: .lb,
            calendar: calendar
        )
    }

    private func exercise(named name: String) -> Exercise {
        Exercise(name: name, category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func insertEntry(
        _ context: ModelContext,
        _ exercise: Exercise,
        dayOffset: Int,
        hour: Int,
        weight: Double,
        reps: Int,
        minute: Int = 0
    ) {
        let performedAt = date(dayOffset: dayOffset, hour: hour, minute: minute)
        context.insert(SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: weight,
            weightUnit: .lb,
            reps: reps,
            restAfterSeconds: exercise.defaultRestSeconds,
            createdAt: performedAt,
            updatedAt: performedAt
        ))
    }

    private func date(dayOffset: Int, hour: Int, minute: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
