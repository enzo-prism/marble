import XCTest
@testable import marble

/// The no-model path of "Ask your journal": keyword intents, exercise
/// resolution through `ExerciseMatcher`, and time phrases, against a fixed
/// clock (Wed 2025-01-15 12:00 UTC, weeks start Sunday).
@MainActor
final class JournalQuestionMatcherTests: MarbleTestCase {
    private let bench = ExerciseMatcher.Candidate(id: UUID(), name: "Bench Press")
    private let incline = ExerciseMatcher.Candidate(id: UUID(), name: "Incline Bench Press")
    private let squat = ExerciseMatcher.Candidate(id: UUID(), name: "Back Squat")
    private let deadlift = ExerciseMatcher.Candidate(id: UUID(), name: "Deadlift")
    private let pullUp = ExerciseMatcher.Candidate(id: UUID(), name: "Pull-Up")
    private let sprint = ExerciseMatcher.Candidate(id: UUID(), name: "Sprint")

    private var matcher: JournalQuestionMatcher {
        JournalQuestionMatcher(
            library: [bench, incline, squat, deadlift, pullUp, sprint],
            preferredUnit: .lb,
            now: now,
            calendar: Self.stableCalendar
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.stableCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Intents

    func testLastTimeQuestions() {
        XCTAssertEqual(matcher.query(for: "When did I last bench?"), .lastPerformed(exerciseID: bench.id, atLeast: nil))
        XCTAssertEqual(matcher.query(for: "last time I benched 185"), .lastPerformed(exerciseID: bench.id, atLeast: WeightThreshold(value: 185, unit: .lb)))
        XCTAssertEqual(matcher.query(for: "When did I last squat 100 kg?"), .lastPerformed(exerciseID: squat.id, atLeast: WeightThreshold(value: 100, unit: .kg)))
        XCTAssertEqual(matcher.query(for: "Most recent incline bench press at 135?"), .lastPerformed(exerciseID: incline.id, atLeast: WeightThreshold(value: 135, unit: .lb)))
        // An exercise alone reads as "when did I last do it".
        XCTAssertEqual(matcher.query(for: "deadlift?"), .lastPerformed(exerciseID: deadlift.id, atLeast: nil))
    }

    func testBestQuestions() {
        XCTAssertEqual(matcher.query(for: "What's my heaviest deadlift?"), .best(exerciseID: deadlift.id, measure: .heaviest, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(matcher.query(for: "What's my bench PR this year?"), .best(exerciseID: bench.id, measure: .automatic, period: .thisYear, distanceMeters: nil))
        XCTAssertEqual(matcher.query(for: "Most reps on pull-ups"), .best(exerciseID: pullUp.id, measure: .mostReps, period: .allTime, distanceMeters: nil))
        XCTAssertEqual(matcher.query(for: "fastest 100m sprint ever"), .best(exerciseID: sprint.id, measure: .fastest, period: .allTime, distanceMeters: 100))
        // A best with no exercise is not something the engine can answer.
        XCTAssertNil(matcher.query(for: "What's my best?"))
    }

    func testCountQuestions() {
        XCTAssertEqual(matcher.query(for: "How many sets did I do this week?"), .totals(period: .thisWeek, exerciseID: nil))
        XCTAssertEqual(matcher.query(for: "How much volume on bench last month?"), .totals(period: .lastMonth, exerciseID: bench.id))
        XCTAssertEqual(matcher.query(for: "How many workouts in the last 30 days"), .totals(period: .lastDays(30), exerciseID: nil))
        XCTAssertEqual(matcher.query(for: "total sets ever"), .totals(period: .allTime, exerciseID: nil))
        XCTAssertEqual(matcher.query(for: "squat this month"), .totals(period: .thisMonth, exerciseID: squat.id))
    }

    func testWorkoutQuestions() {
        XCTAssertEqual(matcher.query(for: "What did I train last week?"), .sessions(period: .lastWeek))
        XCTAssertEqual(matcher.query(for: "When was my last workout?"), .recentSession(matching: ""))
        XCTAssertEqual(matcher.query(for: "When was my last leg day?"), .recentSession(matching: "leg day"))
        XCTAssertEqual(matcher.query(for: "Show my workouts"), .sessions(period: .allTime))
    }

    func testUnrelatedQuestionsAreNotGuessed() {
        XCTAssertNil(matcher.query(for: "Tell me a joke"))
        XCTAssertNil(matcher.query(for: "What's the weather like?"))
        XCTAssertNil(matcher.query(for: ""))
    }

    func testEmptyLibraryFallsBackToWorkoutSearch() {
        let empty = JournalQuestionMatcher(library: [], preferredUnit: .kg, now: now, calendar: Self.stableCalendar)
        XCTAssertEqual(empty.query(for: "When did I last bench?"), .recentSession(matching: "bench"))
    }

    func testEveryExampleQuestionIsUnderstood() {
        let examples = [
            "When did I last do Bench Press?",
            "What's my heaviest Bench Press?",
            "What's my best Pull-Up?",
            "When was my last workout?",
            "How many sets did I do this week?",
            "What did I train last week?"
        ]
        for example in examples {
            XCTAssertNotNil(matcher.query(for: example), example)
        }
    }

    // MARK: - Pieces

    func testExerciseMentionsPreferTheMostRecentlyLoggedOnTies() {
        let barbellRow = ExerciseMatcher.Candidate(id: UUID(), name: "Barbell Row")
        let cableRow = ExerciseMatcher.Candidate(id: UUID(), name: "Cable Row")
        let recentFirst = JournalQuestionMatcher(library: [cableRow, barbellRow], preferredUnit: .lb, now: now, calendar: Self.stableCalendar)
        XCTAssertEqual(recentFirst.reading(of: "when did I last row").exercise, cableRow)
        // A longer exact phrase beats the ambiguous single word.
        XCTAssertEqual(recentFirst.reading(of: "last barbell row").exercise, barbellRow)
    }

    func testTokensFoldCommonVerbForms() {
        XCTAssertEqual(JournalQuestionMatcher.tokens("Squatting, benched & ran!"), ["squat", "bench", "run"])
        XCTAssertEqual(JournalQuestionMatcher.tokens("press"), ["press"])
    }

    func testThresholdAndDistanceParsing() {
        XCTAssertEqual(JournalQuestionMatcher.threshold(in: "at 100", preferredUnit: .kg), WeightThreshold(value: 100, unit: .kg))
        XCTAssertEqual(JournalQuestionMatcher.threshold(in: "over 225 lbs", preferredUnit: .kg), WeightThreshold(value: 225, unit: .lb))
        XCTAssertNil(JournalQuestionMatcher.threshold(in: "did 5 sets of 10 reps", preferredUnit: .lb))
        XCTAssertNil(JournalQuestionMatcher.threshold(in: "my 100m sprint", preferredUnit: .lb))
        XCTAssertEqual(JournalQuestionMatcher.distanceMeters(in: "60 meters"), 60)
        XCTAssertEqual(JournalQuestionMatcher.distanceMeters(in: "1 mile")!, 1609.344, accuracy: 0.001)
        XCTAssertNil(JournalQuestionMatcher.distanceMeters(in: "bench 185"))
    }

    // MARK: - Time phrases

    func testTimePhrasesResolveToTheRightIntervals() {
        let cal = Self.stableCalendar
        func interval(_ text: String) -> DateInterval? {
            JournalTimeParser.period(in: text, now: now, calendar: cal)?.interval(now: now, calendar: cal)
        }
        XCTAssertEqual(interval("this week"), DateInterval(start: date(2025, 1, 12), end: date(2025, 1, 19)))
        XCTAssertEqual(interval("last week"), DateInterval(start: date(2025, 1, 5), end: date(2025, 1, 12)))
        XCTAssertEqual(interval("this month"), DateInterval(start: date(2025, 1, 1), end: date(2025, 2, 1)))
        XCTAssertEqual(interval("last month"), DateInterval(start: date(2024, 12, 1), end: date(2025, 1, 1)))
        XCTAssertEqual(interval("in the last 7 days"), DateInterval(start: date(2025, 1, 9), end: date(2025, 1, 16)))
        XCTAssertEqual(interval("past 2 weeks"), DateInterval(start: date(2025, 1, 2), end: date(2025, 1, 16)))
        XCTAssertEqual(interval("today"), DateInterval(start: date(2025, 1, 15), end: date(2025, 1, 16)))
        XCTAssertEqual(interval("yesterday"), DateInterval(start: date(2025, 1, 14), end: date(2025, 1, 15)))
        XCTAssertEqual(interval("2025-01-02 to 2025-01-05"), DateInterval(start: date(2025, 1, 2), end: date(2025, 1, 6)))
        XCTAssertEqual(interval("on 2024-12-31"), DateInterval(start: date(2024, 12, 31), end: date(2025, 1, 1)))
        // A month later in the year than now means last year's.
        XCTAssertEqual(interval("in October"), DateInterval(start: date(2024, 10, 1), end: date(2024, 11, 1)))
        XCTAssertEqual(interval("january 2024"), DateInterval(start: date(2024, 1, 1), end: date(2024, 2, 1)))
        XCTAssertNil(interval("all time"))
        XCTAssertEqual(JournalTimeParser.period(in: "ever", now: now, calendar: cal), .allTime)
    }

    func testTimeParserIgnoresLookalikes() {
        let cal = Self.stableCalendar
        XCTAssertNil(JournalTimeParser.period(in: "when did I last bench", now: now, calendar: cal))
        XCTAssertNil(JournalTimeParser.period(in: "may I see my squat", now: now, calendar: cal))
        XCTAssertNil(JournalTimeParser.period(in: "2025-02-31", now: now, calendar: cal))
        XCTAssertEqual(JournalTimeParser.period(in: "in may", now: now, calendar: cal), .month(year: 2024, month: 5))
        XCTAssertEqual(
            JournalTimeParser.matches(in: "this week vs last week", now: now, calendar: cal).map(\.period),
            [.thisWeek, .lastWeek]
        )
    }

    func testYearsAreRangesNeverLoads() {
        XCTAssertEqual(matcher.query(for: "How many sets did I do in 2025?"), .totals(period: .year(2025), exerciseID: nil))
        XCTAssertEqual(matcher.query(for: "heaviest bench during 2024"), .best(exerciseID: bench.id, measure: .heaviest, period: .year(2024), distanceMeters: nil))
        XCTAssertEqual(matcher.query(for: "squat volume 2024"), .totals(period: .year(2024), exerciseID: squat.id))
        // A year is never a load, even when the time parser doesn't claim it.
        XCTAssertNil(JournalQuestionMatcher.threshold(in: "benched in 2025", preferredUnit: .lb))
        XCTAssertNil(JournalQuestionMatcher.threshold(in: "at 2000", preferredUnit: .lb))
        // With a unit it is a load.
        XCTAssertEqual(matcher.query(for: "last deadlift at 2000 lb"), .lastPerformed(exerciseID: deadlift.id, atLeast: WeightThreshold(value: 2000, unit: .lb)))
        XCTAssertEqual(matcher.reading(of: "last bench 185 in 2024").threshold, WeightThreshold(value: 185, unit: .lb))

        let cal = Self.stableCalendar
        XCTAssertEqual(JournalPeriod.year(2025).interval(now: now, calendar: cal), DateInterval(start: date(2025, 1, 1), end: date(2026, 1, 1)))
        XCTAssertEqual(JournalPeriod.year(2025).label(calendar: cal), "in 2025")
    }

    func testSincePhrasesAreOpenEndedThroughToday() {
        let cal = Self.stableCalendar
        let throughToday = date(2025, 1, 16)
        func period(_ text: String) -> JournalPeriod? { JournalTimeParser.period(in: text, now: now, calendar: cal) }
        // A month later in the year than now means last year's.
        XCTAssertEqual(period("since October"), .between(start: date(2024, 10, 1), end: throughToday))
        XCTAssertEqual(period("since Jan 5"), .between(start: date(2025, 1, 5), end: throughToday))
        XCTAssertEqual(period("since Jan 20"), .between(start: date(2024, 1, 20), end: throughToday))
        XCTAssertEqual(period("since November 3rd, 2024"), .between(start: date(2024, 11, 3), end: throughToday))
        XCTAssertEqual(period("since October 2024"), .between(start: date(2024, 10, 1), end: throughToday))
        XCTAssertEqual(period("since 2024"), .between(start: date(2024, 1, 1), end: throughToday))
        XCTAssertEqual(period("since 2024-12-25"), .between(start: date(2024, 12, 25), end: throughToday))
        XCTAssertEqual(matcher.query(for: "How many sets since October?"), .totals(period: .between(start: date(2024, 10, 1), end: throughToday), exerciseID: nil))
    }

    func testPeriodLabels() {
        let cal = Self.stableCalendar
        XCTAssertEqual(JournalPeriod.lastDays(30).label(calendar: cal), "in the last 30 days")
        XCTAssertEqual(JournalPeriod.month(year: 2024, month: 10).label(calendar: cal), "in October 2024")
        XCTAssertEqual(JournalPeriod.between(start: date(2025, 1, 2), end: date(2025, 1, 6)).label(calendar: cal), "from Jan 2, 2025 to Jan 5, 2025")
        XCTAssertEqual(JournalPeriod.between(start: date(2025, 1, 2), end: date(2025, 1, 3)).label(calendar: cal), "on Jan 2, 2025")
    }
}
