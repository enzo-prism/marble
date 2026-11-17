import SwiftData
import XCTest
@testable import marble

/// The deterministic engine behind "Ask your journal". Every number Ask shows
/// comes from here, so units, ranges, ties, sprint tenths and imported sets
/// are pinned against a fixed clock (Wed 2025-01-15 12:00 UTC, weeks start
/// Sunday) and a stable UTC calendar.
@MainActor
final class JournalQueryEngineTests: MarbleTestCase {
    private lazy var context: ModelContext = makeInMemoryContext()

    // MARK: - Fixtures

    private func engine(_ unit: WeightUnit = .lb) -> JournalQueryEngine {
        JournalQueryEngine(context: context, unit: unit, now: now, calendar: Self.stableCalendar)
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = Self.stableCalendar.startOfDay(for: now)
        let shifted = Self.stableCalendar.date(byAdding: .day, value: offset, to: start)!
        return shifted.addingTimeInterval(TimeInterval(hour * 3600))
    }

    @discardableResult
    private func exercise(
        _ name: String,
        metrics: ExerciseMetricsProfile = .weightAndRepsRequired,
        style: ResistanceTrackingStyle = .totalLoad,
        category: ExerciseCategory = .chest
    ) -> Exercise {
        let exercise = Exercise(name: name, category: category, resistanceTrackingStyle: style, metrics: metrics, defaultRestSeconds: 90)
        context.insert(exercise)
        return exercise
    }

    @discardableResult
    private func set(
        _ exercise: Exercise,
        _ date: Date,
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .meters,
        seconds: Int? = nil
    ) -> SetEntry {
        let entry = SetEntry(
            exercise: exercise, performedAt: date, weight: weight, weightUnit: unit, reps: reps,
            distance: distance, distanceUnit: distanceUnit, durationSeconds: seconds,
            restAfterSeconds: 90, createdAt: date, updatedAt: date
        )
        context.insert(entry)
        return entry
    }

    @discardableResult
    private func session(_ title: String, _ date: Date, entries: [SetEntry] = [], finished: Bool = true) -> WorkoutSession {
        let session = WorkoutSession(
            title: title, startedAt: date, endedAt: finished ? date.addingTimeInterval(3900) : nil,
            createdAt: date, updatedAt: date, entries: entries
        )
        context.insert(session)
        return session
    }

    // MARK: - Empty journal

    func testEmptyJournalAnswersHonestlyForEveryQuery() {
        let queries: [JournalQuery] = [
            .lastPerformed(exerciseID: UUID(), atLeast: nil),
            .best(exerciseID: UUID(), measure: .automatic, period: .allTime, distanceMeters: nil),
            .totals(period: .thisWeek, exerciseID: nil),
            .recentSession(matching: ""),
            .sessions(period: .thisMonth)
        ]
        for query in queries {
            let result = engine().run(query)
            XCTAssertFalse(result.found, "\(query)")
            XCTAssertTrue(result.cards.isEmpty, "\(query)")
            XCTAssertEqual(result.sentence, "Your journal is empty so far. Log a set, then ask again.")
        }
        XCTAssertEqual(engine().exampleQuestions().count, 3)
        XCTAssertEqual(engine().exampleQuestions().first, "When was my last workout?")
    }

    func testUnknownExerciseIsReportedNotInvented() {
        let bench = exercise("Bench Press")
        set(bench, day(-1), weight: 185, reps: 5)
        let result = engine().run(.lastPerformed(exerciseID: UUID(), atLeast: nil))
        XCTAssertFalse(result.found)
        XCTAssertEqual(result.sentence, "That exercise isn't in your library.")
    }

    // MARK: - Last performed

    func testLastPerformedReportsThatDaysSetCountAndTopSet() {
        let bench = exercise("Bench Press")
        set(bench, day(-10), weight: 225, reps: 3)
        set(bench, day(-3, hour: 9), weight: 185, reps: 8)
        set(bench, day(-3, hour: 10), weight: 205, reps: 5)
        set(bench, day(-3, hour: 11), weight: 195, reps: 6)
        let result = engine().run(.lastPerformed(exerciseID: bench.id, atLeast: nil))
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.sentence, "You last did Bench Press on Jan 12, 2025 (3 days ago): 3 sets, top set 205 lb × 5.")
        XCTAssertTrue(result.facts.contains("Sets of Bench Press that day: 3"))
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards.first?.value, "205 lb × 5")
        XCTAssertEqual(result.cards.first?.destination, .exercise(bench.id))
    }

    func testLastPerformedWithThresholdComparesAcrossUnits() {
        let bench = exercise("Bench Press")
        set(bench, day(-2), weight: 90, unit: .kg, reps: 5)    // 198.4 lb — below 200 lb
        set(bench, day(-5), weight: 100, unit: .kg, reps: 3)   // 220.5 lb — the answer
        set(bench, day(-9), weight: 230, unit: .lb, reps: 1)
        let threshold = WeightThreshold(value: 200, unit: .lb)
        let result = engine(.lb).run(.lastPerformed(exerciseID: bench.id, atLeast: threshold))
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.sentence, "The last time you did Bench Press at 200 lb or more was Jan 10, 2025 (5 days ago): 220.5 lb × 3.")
        XCTAssertTrue(result.facts.contains("Logged as: 100 kg"))
        XCTAssertTrue(result.cards.first?.detail.contains("logged as 100 kg") ?? false)

        let none = engine(.lb).run(.lastPerformed(exerciseID: bench.id, atLeast: WeightThreshold(value: 300, unit: .lb)))
        XCTAssertFalse(none.found)
        XCTAssertEqual(none.sentence, "No Bench Press sets at 300 lb or more are in your journal.")
    }

    func testLastPerformedThresholdPagesPastTheFirstPage() {
        let squat = exercise("Back Squat", category: .quads)
        set(squat, day(-400), weight: 315, reps: 1)
        for index in 0..<(JournalQueryEngine.thresholdPageSize + 20) {
            set(squat, day(-1).addingTimeInterval(TimeInterval(-index * 60)), weight: 135, reps: 5)
        }
        let result = engine().run(.lastPerformed(exerciseID: squat.id, atLeast: WeightThreshold(value: 300, unit: .lb)))
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.cards.first?.value, "315 lb × 1")
    }

    func testLastPerformedLinksToTheWorkoutThatHoldsTheSet() {
        let bench = exercise("Bench Press")
        let entry = set(bench, day(-1), weight: 185, reps: 5)
        let workout = session("Upper Body", day(-1, hour: 9), entries: [entry])
        let result = engine().run(.lastPerformed(exerciseID: bench.id, atLeast: nil))
        XCTAssertEqual(result.cards.first?.destination, .session(workout.id))
        XCTAssertTrue(result.facts.contains("Workout: Upper Body"))
        XCTAssertEqual(result.sentence, "You last did Bench Press on Jan 14, 2025 (yesterday): 1 set, top set 185 lb × 5.")
    }

    // MARK: - Bests

    func testHeaviestComparesAcrossUnitsAndShowsThePreferredUnit() {
        let bench = exercise("Bench Press")
        set(bench, day(-20), weight: 100, unit: .kg, reps: 5)   // 100 kg
        set(bench, day(-6), weight: 225, unit: .lb, reps: 5)    // 102.06 kg — heaviest

        let pounds = engine(.lb).run(.best(exerciseID: bench.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(pounds.sentence, "Your heaviest Bench Press set is 225 lb × 5, on Jan 9, 2025.")
        XCTAssertFalse(pounds.facts.contains { $0.hasPrefix("Logged as") })

        let kilos = engine(.kg).run(.best(exerciseID: bench.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(kilos.sentence, "Your heaviest Bench Press set is 102.1 kg × 5, on Jan 9, 2025.")
        XCTAssertTrue(kilos.facts.contains("Logged as: 225 lb"))
    }

    func testHeaviestTiesBreakOnRepsThenTheLaterSet() {
        let bench = exercise("Bench Press")
        set(bench, day(-10), weight: 200, reps: 5)
        set(bench, day(-20), weight: 200, reps: 6)
        var result = engine().run(.best(exerciseID: bench.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.cards.first?.value, "200 lb × 6")

        let row = exercise("Barbell Row", category: .back)
        set(row, day(-8), weight: 155, reps: 8)
        set(row, day(-4), weight: 155, reps: 8)
        result = engine().run(.best(exerciseID: row.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertTrue(result.sentence.hasSuffix("on Jan 11, 2025."), result.sentence)
    }

    func testMostRepsTiesBreakOnWeight() {
        let pullUp = exercise("Pull-Up", metrics: ExerciseMetricsProfile(weight: .optional, reps: .required, durationSeconds: .none), category: .back)
        set(pullUp, day(-3), reps: 12)
        set(pullUp, day(-6), weight: 25, reps: 12)
        set(pullUp, day(-9), reps: 10)
        let result = engine().run(.best(exerciseID: pullUp.id, measure: .mostReps, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.sentence, "Your most reps on Pull-Up: 25 lb × 12, on Jan 9, 2025.")
    }

    func testAutomaticMeasureFollowsTheExercisesMetrics() {
        let pushUp = exercise("Push-Up", metrics: .repsOnlyRequired)
        set(pushUp, day(-2), reps: 30)
        set(pushUp, day(-4), reps: 42)
        let result = engine().run(.best(exerciseID: pushUp.id, measure: .automatic, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.cards.first?.label, "Most reps")
        XCTAssertEqual(result.cards.first?.value, "42 reps")
    }

    func testBestRespectsThePeriod() {
        let bench = exercise("Bench Press")
        set(bench, day(-40), weight: 245, reps: 1)
        set(bench, day(-2), weight: 205, reps: 3)
        let result = engine().run(.best(exerciseID: bench.id, measure: .heaviest, period: .thisMonth, distanceMeters: nil))
        XCTAssertEqual(result.sentence, "Your heaviest Bench Press set this month is 205 lb × 3, on Jan 13, 2025.")
        let empty = engine().run(.best(exerciseID: bench.id, measure: .heaviest, period: .today, distanceMeters: nil))
        XCTAssertFalse(empty.found)
        XCTAssertEqual(empty.sentence, "No weighted Bench Press sets were logged today.")
    }

    func testFastestPrefersTenthsAndTheMostTimedDistance() {
        let sprint = exercise("Sprint", metrics: .distanceAndDurationRequired, category: .run)
        set(sprint, day(-5), distance: 100, seconds: 15)                   // legacy whole seconds: 15.0s
        let precise = set(sprint, day(-3), distance: 100, seconds: 15)     // 14.8s via SprintRepDetail
        context.insert(SprintRepDetail(setEntryID: precise.id, durationTenths: 148, targetLowerTenths: 140, targetUpperTenths: 150))
        set(sprint, day(-1), distance: 60, seconds: 8)

        let fastest = engine().run(.best(exerciseID: sprint.id, measure: .fastest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(fastest.sentence, "Your fastest 100 m Sprint is 14.8s, on Jan 12, 2025.")
        XCTAssertEqual(fastest.cards.first?.label, "Fastest 100 m")
        XCTAssertEqual(fastest.cards.first?.value, "100 m in 14.8s")

        let sixty = engine().run(.best(exerciseID: sprint.id, measure: .automatic, period: .allTime, distanceMeters: 60))
        XCTAssertEqual(sixty.sentence, "Your fastest 60 m Sprint is 8.0s, on Jan 14, 2025.")
    }

    func testFastestTiesPreferTheLaterRep() {
        let sprint = exercise("Sprint", metrics: .distanceAndDurationRequired, category: .run)
        set(sprint, day(-7), distance: 100, seconds: 14)
        set(sprint, day(-2), distance: 0.1, distanceUnit: .kilometers, seconds: 14)   // same distance, other unit
        let result = engine().run(.best(exerciseID: sprint.id, measure: .fastest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.sentence, "Your fastest 0.1 km Sprint is 14.0s, on Jan 13, 2025.")
    }

    func testLongestHoldReadsAsADuration() {
        let plank = exercise("Plank", metrics: .durationOnlyRequired, category: .core)
        set(plank, day(-2), seconds: 60)
        set(plank, day(-5), seconds: 90)
        let result = engine().run(.best(exerciseID: plank.id, measure: .automatic, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.sentence, "Your longest Plank is 1m 30s, on Jan 10, 2025.")
    }

    func testDumbbellPairsShowPerHandWeight() {
        let press = exercise("Dumbbell Press", style: .singleDumbbellPair)
        set(press, day(-1), weight: 100, reps: 10)   // stored as the pair total
        let result = engine().run(.best(exerciseID: press.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(result.cards.first?.value, "50 lb each × 10")
    }

    // MARK: - Totals

    func testTotalsCountManualAndImportedSetsWithVolumeInEitherUnit() {
        let bench = exercise("Bench Press")
        let run = exercise("Outdoor Run", metrics: .distanceAndDurationRequired, category: .run)
        set(bench, day(-1), weight: 100, reps: 10)
        set(bench, day(-1, hour: 11), weight: 100, reps: 10)
        set(bench, day(0, hour: 8), weight: 50, unit: .kg, reps: 10)
        let imported = ImportedWorkout(source: .appleHealth, externalID: "run-1", title: "Run", workoutDate: day(-2), setsImported: 1)
        context.insert(imported)
        let runSet = set(run, day(-2), distance: 5, distanceUnit: .kilometers, seconds: 1500)
        runSet.importedWorkout = imported
        set(bench, day(-9), weight: 300, reps: 10)   // last week: excluded
        session("Push", day(-1, hour: 9), entries: [])

        let pounds = engine(.lb).run(.totals(period: .thisWeek, exerciseID: nil))
        XCTAssertTrue(pounds.found)
        XCTAssertEqual(pounds.sentence, "This week: 4 sets across 3 training days, 3,102 lb of volume.")
        XCTAssertTrue(pounds.facts.contains("Recorded workouts: 1"))
        XCTAssertTrue(pounds.facts.contains("Dates: Jan 12, 2025 to Jan 18, 2025"))

        let kilos = engine(.kg).run(.totals(period: .thisWeek, exerciseID: nil))
        XCTAssertEqual(kilos.sentence, "This week: 4 sets across 3 training days, 1.4t of volume.")

        let benchOnly = engine(.lb).run(.totals(period: .thisWeek, exerciseID: bench.id))
        XCTAssertEqual(benchOnly.sentence, "Bench Press this week: 3 sets across 2 days, 3,102 lb of volume.")
        XCTAssertEqual(benchOnly.cards.first?.destination, .exercise(bench.id))
    }

    func testTotalsRangeBoundaries() {
        let bench = exercise("Bench Press")
        set(bench, day(-6, hour: 0), weight: 100, reps: 1)     // first day of "last 7 days"
        set(bench, day(-7, hour: 23), weight: 100, reps: 1)    // just outside
        set(bench, day(0, hour: 11), weight: 100, reps: 1)     // today

        XCTAssertEqual(engine().run(.totals(period: .lastDays(7), exerciseID: nil)).facts.first { $0.hasPrefix("Sets:") }, "Sets: 2")
        XCTAssertEqual(engine().run(.totals(period: .today, exerciseID: nil)).facts.first { $0.hasPrefix("Sets:") }, "Sets: 1")

        let cal = Self.stableCalendar
        let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 8))!
        let endExclusive = cal.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let explicit = engine().run(.totals(period: .between(start: start, end: endExclusive), exerciseID: nil))
        XCTAssertEqual(explicit.facts.first { $0.hasPrefix("Sets:") }, "Sets: 2")
        XCTAssertTrue(explicit.sentence.hasPrefix("From Jan 8, 2025 to Jan 9, 2025: 2 sets"), explicit.sentence)

        let none = engine().run(.totals(period: .lastMonth, exerciseID: nil))
        XCTAssertFalse(none.found)
        XCTAssertEqual(none.sentence, "No sets were logged last month.")
    }

    func testAllTimeTotalsReadAsInTotal() {
        let bench = exercise("Bench Press")
        set(bench, day(-100), weight: 135, reps: 10)
        let result = engine().run(.totals(period: .allTime, exerciseID: nil))
        XCTAssertEqual(result.sentence, "In total: 1 set across 1 training day, 1,350 lb of volume.")
    }

    // MARK: - Workouts

    func testRecentSessionMatchesTitleOrExerciseAndSkipsActiveWorkouts() {
        let squat = exercise("Back Squat", category: .quads)
        let bench = exercise("Bench Press")
        let squatSet = set(squat, day(-4), weight: 225, reps: 5)
        session("Leg Day", day(-4, hour: 9), entries: [squatSet])
        let benchSet = set(bench, day(-2), weight: 185, reps: 5)
        session("Push", day(-2, hour: 9), entries: [benchSet])
        session("In progress", day(0, hour: 9), finished: false)

        let latest = engine().run(.recentSession(matching: ""))
        XCTAssertEqual(latest.sentence, "Your most recent workout was Push on Jan 13, 2025 (2 days ago): 1 set in 1h 5m.")

        let byTitle = engine().run(.recentSession(matching: "leg day"))
        XCTAssertEqual(byTitle.cards.first?.title, "Leg Day")
        let byExercise = engine().run(.recentSession(matching: "squat"))
        XCTAssertEqual(byExercise.cards.first?.title, "Leg Day")
        XCTAssertEqual(byExercise.cards.first?.value, "1 set · 1h 5m")

        let missing = engine().run(.recentSession(matching: "yoga"))
        XCTAssertFalse(missing.found)
        XCTAssertEqual(missing.sentence, "No completed workouts matching “yoga” are in your history yet.")
    }

    func testSessionListCapsCardsButCountsEverything() {
        let bench = exercise("Bench Press")
        for offset in 0..<7 {
            let entry = set(bench, day(-offset - 1), weight: 135, reps: 5)
            session("Workout \(offset)", day(-offset - 1, hour: 9), entries: [entry])
        }
        let result = engine().run(.sessions(period: .thisMonth))
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.cards.count, JournalQueryEngine.sessionListLimit)
        XCTAssertEqual(result.sentence, "You recorded 7 workouts this month; the latest was Workout 0 on Jan 14, 2025.")
        XCTAssertTrue(result.facts.contains("Showing the latest 5 of 7."))
        XCTAssertEqual(result.cards.first?.destination?.isSession, true)
    }

    func testEmptySessionListMentionsSetsLoggedOutsideWorkouts() {
        let bench = exercise("Bench Press")
        set(bench, day(-1), weight: 135, reps: 5)
        set(bench, day(-1, hour: 11), weight: 135, reps: 5)
        let result = engine().run(.sessions(period: .thisWeek))
        XCTAssertFalse(result.found)
        XCTAssertEqual(result.sentence, "No recorded workouts this week, though 2 sets are in your log.")
    }

    // MARK: - Provenance + library

    func testImportedSetsAreLabelledOnTheirCard() {
        let run = exercise("Outdoor Run", metrics: .distanceAndDurationRequired, category: .run)
        let imported = ImportedWorkout(source: .appleHealth, externalID: "run-2", title: "Run", workoutDate: day(-1), setsImported: 1)
        context.insert(imported)
        let entry = set(run, day(-1), distance: 5, distanceUnit: .kilometers, seconds: 1500)
        entry.importedWorkout = imported
        let result = engine().run(.lastPerformed(exerciseID: run.id, atLeast: nil))
        XCTAssertEqual(result.cards.first?.value, "5 km in 25:00.0")
        XCTAssertTrue(result.cards.first?.detail.contains("Imported from Apple Health") ?? false)
        XCTAssertTrue(result.facts.contains("Imported from Apple Health"))
    }

    func testLibraryPrefersRecentlyLoggedExercisesAndExamplesUseThem() {
        exercise("Abs Roller", category: .core)
        let deadlift = exercise("Deadlift", category: .back)
        set(deadlift, day(-1), weight: 315, reps: 3)
        XCTAssertEqual(engine().library().first?.name, "Deadlift")
        XCTAssertEqual(engine().exampleQuestions(), [
            "When did I last do Deadlift?",
            "What's my heaviest Deadlift?",
            "How many sets did I do this week?",
            "What did I train last week?"
        ])
        XCTAssertEqual(engine().resolveExercise(named: "deadlifts")?.id, deadlift.id)
    }
}

private extension JournalCard.Destination {
    var isSession: Bool {
        if case .session = self { return true }
        return false
    }
}
