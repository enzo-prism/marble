import XCTest
@testable import marble

@MainActor
final class DailyHighlightsTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testDefaultWindowStartsAtEightAndEndsAtMidnight() throws {
        let window = DailyHighlightWindow(
            startMinute: DailyHighlightWindow.defaultStartMinute,
            endMinute: DailyHighlightWindow.defaultEndMinute
        )

        XCTAssertNil(window.occurrence(containing: date(dayOffset: 0, hour: 19, minute: 59), calendar: calendar))
        XCTAssertNotNil(window.occurrence(containing: date(dayOffset: 0, hour: 20, minute: 0), calendar: calendar))
        XCTAssertNotNil(window.occurrence(containing: date(dayOffset: 0, hour: 23, minute: 59, second: 59), calendar: calendar))
        XCTAssertNil(window.occurrence(containing: date(dayOffset: 1, hour: 0, minute: 0), calendar: calendar))

        let occurrence = try XCTUnwrap(window.occurrence(
            containing: date(dayOffset: 0, hour: 20, minute: 0),
            calendar: calendar
        ))
        XCTAssertEqual(occurrence.interval.end, calendar.startOfDay(for: date(dayOffset: 1, hour: 0, minute: 0)))
    }

    func testOvernightWindowAnchorsAfterMidnightToPriorCelebrationDay() throws {
        let window = DailyHighlightWindow(startMinute: 22 * 60, endMinute: 2 * 60)
        let beforeMidnight = try XCTUnwrap(window.occurrence(
            containing: date(dayOffset: 0, hour: 23, minute: 0),
            calendar: calendar
        ))
        let afterMidnight = try XCTUnwrap(window.occurrence(
            containing: date(dayOffset: 1, hour: 1, minute: 30),
            calendar: calendar
        ))

        XCTAssertEqual(beforeMidnight.celebrationDay, afterMidnight.celebrationDay)
        XCTAssertNil(window.occurrence(
            containing: date(dayOffset: 1, hour: 2, minute: 1),
            calendar: calendar
        ))
    }

    func testEqualTimesAreInvalidRatherThanAlwaysVisible() {
        let window = DailyHighlightWindow(startMinute: 20 * 60, endMinute: 20 * 60)
        XCTAssertFalse(window.isValid)
        XCTAssertNil(window.occurrence(containing: now, calendar: calendar))
    }

    func testDSTGapAndRepeatedHourProduceUsableOccurrences() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let springDay = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2025, month: 3, day: 9)))
        let springMoment = try XCTUnwrap(losAngeles.date(bySettingHour: 3, minute: 1, second: 0, of: springDay))
        let spring = DailyHighlightWindow(startMinute: 2 * 60 + 30, endMinute: 4 * 60)
        let springOccurrence = try XCTUnwrap(spring.occurrence(containing: springMoment, calendar: losAngeles))
        XCTAssertLessThan(springOccurrence.interval.start, springOccurrence.interval.end)

        let fallDay = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2025, month: 11, day: 2)))
        let fallMoment = try XCTUnwrap(losAngeles.date(bySettingHour: 1, minute: 45, second: 0, of: fallDay))
        let fall = DailyHighlightWindow(startMinute: 60 + 15, endMinute: 60 + 50)
        let fallOccurrence = try XCTUnwrap(fall.occurrence(containing: fallMoment, calendar: losAngeles))
        XCTAssertLessThan(fallOccurrence.interval.start, fallOccurrence.interval.end)
    }

    func testEmptyAndFutureOnlyDaysStayHidden() throws {
        let occurrence = try defaultOccurrence()
        XCTAssertNil(build(history: [], occurrence: occurrence))

        let exercise = lift()
        let future = entry(exercise, dayOffset: 0, hour: 22, weight: 225, reps: 5)
        let summary = DailyHighlightsBuilder.build(
            history: [future],
            occurrence: occurrence,
            now: date(dayOffset: 0, hour: 21, minute: 0),
            displayWeightUnit: .lb,
            calendar: calendar
        )
        XCTAssertNil(summary)
    }

    func testFirstExerciseLogIsCelebratedWithoutCallingItAPersonalRecord() throws {
        let exercise = lift()
        let first = entry(exercise, dayOffset: 0, hour: 18, weight: 185, reps: 5)

        let summary = try XCTUnwrap(build(history: [first], occurrence: defaultOccurrence()))

        XCTAssertEqual(summary.personalRecordCount, 0)
        XCTAssertEqual(summary.headline, "You showed up.")
        XCTAssertEqual(summary.achievements.first?.kind, .dailyBest)
        XCTAssertEqual(summary.achievements.first?.detail, "Today's work")
    }

    func testMixedUnitWeightRecordAndBodyweightRepRecordAreGenuine() throws {
        let bench = lift(name: "Bench Press")
        let pullUps = Exercise(name: "Pull-Ups", category: .back, metrics: .repsOnlyRequired, defaultRestSeconds: 60)
        let history = [
            entry(bench, dayOffset: -3, hour: 10, weight: 100, unit: .kg, reps: 5),
            entry(pullUps, dayOffset: -3, hour: 10, reps: 10),
            entry(bench, dayOffset: 0, hour: 18, weight: 225, unit: .lb, reps: 5),
            entry(pullUps, dayOffset: 0, hour: 18, reps: 14)
        ]

        let summary = try XCTUnwrap(build(history: history, occurrence: defaultOccurrence()))
        let details = Set(summary.achievements.map(\.detail))

        XCTAssertEqual(summary.personalRecordCount, 2)
        XCTAssertTrue(details.contains("New weight best"))
        XCTAssertTrue(details.contains("New rep best"))
        XCTAssertEqual(summary.headline, "You moved forward.")
    }

    func testRunBestRequiresComparableDistanceAndLowerTime() throws {
        let run = Exercise(name: "5K Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let history = [
            entry(run, dayOffset: -7, hour: 7, distance: 5, distanceUnit: .kilometers, duration: 1_500),
            entry(run, dayOffset: 0, hour: 18, distance: 5_000, distanceUnit: .meters, duration: 1_440)
        ]

        let summary = try XCTUnwrap(build(history: history, occurrence: defaultOccurrence()))
        let achievement = try XCTUnwrap(summary.achievements.first)

        XCTAssertEqual(achievement.kind, .runBest)
        XCTAssertEqual(achievement.detail, "60 seconds faster · new best")
        XCTAssertEqual(summary.headline, "A faster day.")
    }

    func testDailyHighlightIgnoresTrendsRangeAndExerciseFilter() throws {
        let bench = lift(name: "Bench Press")
        let squat = lift(name: "Squat")
        let prior = entry(squat, dayOffset: -2, hour: 10, weight: 200, reps: 5)
        let today = entry(squat, dayOffset: 0, hour: 18, weight: 225, reps: 5)
        let unrelatedRangeRow = entry(bench, dayOffset: 0, hour: 17, weight: 95, reps: 10)

        let derived = TrendsDerivedData.build(
            entries: [unrelatedRangeRow],
            supplementEntries: [],
            historyEntries: [prior, today, unrelatedRangeRow],
            selectedExercise: bench,
            selectedSupplementType: nil,
            range: .sevenDays,
            dailyHighlightOccurrence: try defaultOccurrence(),
            displayWeightUnit: .lb,
            calendar: calendar,
            now: date(dayOffset: 0, hour: 21, minute: 0)
        )

        XCTAssertEqual(derived.dailyHighlight?.achievements.first?.title, "Squat")
    }

    func testQuoteLibraryIsLargeUniqueAndSourceAuditable() {
        let quotes = DailyHighlightQuoteLibrary.all

        // Original 45 plus the 61 extension entries that don't duplicate a
        // bundled text (6 batch entries were dropped as text duplicates;
        // audit follow-up dropped q123/q147/q148 as semantic duplicates or
        // truncations, with q121/q126/q127 replaced in place).
        XCTAssertEqual(quotes.count, 106)
        XCTAssertEqual(Set(quotes.map { $0.id }).count, quotes.count)
        XCTAssertEqual(Set(quotes.map { $0.text }).count, quotes.count)
        XCTAssertTrue(quotes.allSatisfy { !$0.text.isEmpty && !$0.author.isEmpty && !$0.source.isEmpty })
        XCTAssertTrue(quotes.allSatisfy { $0.text.count <= 140 })
        XCTAssertTrue(quotes.allSatisfy { URL(string: $0.sourceURL)?.scheme == "https" })
    }

    func testQuoteSessionOrderIsDeterministicUnderTestHooks() {
        // Unit tests run as an XCTest process, so the session order must be
        // the stable bundled order — never a shuffle.
        XCTAssertEqual(DailyHighlightQuoteLibrary.sessionQuotes, DailyHighlightQuoteLibrary.all)
        XCTAssertEqual(
            Set(DailyHighlightQuoteLibrary.sessionQuotes.map { $0.id }),
            Set(DailyHighlightQuoteLibrary.all.map { $0.id })
        )
    }

    func testQuoteSessionOrderIsStableWithinALaunch() {
        XCTAssertEqual(
            DailyHighlightQuoteLibrary.sessionQuotes.map { $0.id },
            DailyHighlightQuoteLibrary.sessionQuotes.map { $0.id }
        )
    }

    // MARK: - Quote rotation resume

    func testManualQuoteSelectionHoldsForAtLeastOneFullIntervalThenRotationResumes() {
        let selection = DailyHighlightQuoteRotation.ManualSelection(index: 2, tick: 100)

        // Within the tap's own tick and the next one the pick still wins —
        // clearing at the first boundary could dismiss a tap made moments
        // before it.
        for tick in [100, 101] {
            XCTAssertEqual(
                DailyHighlightQuoteRotation.displayedIndex(
                    quoteCount: 3,
                    autoRotates: true,
                    manualSelection: selection,
                    currentTick: tick
                ),
                2
            )
        }

        // From the boundary after that, the shared schedule takes over again.
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: 3,
                autoRotates: true,
                manualSelection: selection,
                currentTick: 102
            ),
            102 % 3
        )
    }

    func testManualQuoteSelectionIsPermanentWhenRotationIsDisabled() {
        // VoiceOver, Reduce Motion, and test runs never rotate — an adjusted
        // quote must stay put no matter how much time passes.
        let selection = DailyHighlightQuoteRotation.ManualSelection(index: 1, tick: 100)

        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: 3,
                autoRotates: false,
                manualSelection: selection,
                currentTick: 10_000
            ),
            1
        )
        // And without a pick, the static variant always shows the first quote.
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: 3,
                autoRotates: false,
                manualSelection: nil,
                currentTick: 10_000
            ),
            0
        )
    }

    func testAutoRotationWalksTheScheduleAndTicksFollowTheClock() {
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: 3,
                autoRotates: true,
                manualSelection: nil,
                currentTick: 7
            ),
            1
        )

        let interval: TimeInterval = 12
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(DailyHighlightQuoteRotation.tick(at: start, interval: interval), 0)
        XCTAssertEqual(
            DailyHighlightQuoteRotation.tick(at: start.addingTimeInterval(interval - 0.5), interval: interval),
            0
        )
        XCTAssertEqual(
            DailyHighlightQuoteRotation.tick(at: start.addingTimeInterval(interval), interval: interval),
            1
        )
    }

    func testAutoRotationWalksTheFullPool() {
        let count = DailyHighlightQuoteLibrary.all.count
        XCTAssertGreaterThan(count, 3)

        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: count,
                autoRotates: true,
                manualSelection: nil,
                currentTick: 7
            ),
            7 % count
        )
        // The schedule wraps cleanly around the larger pool.
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: count,
                autoRotates: true,
                manualSelection: nil,
                currentTick: count
            ),
            0
        )
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: count,
                autoRotates: true,
                manualSelection: nil,
                currentTick: count + 1
            ),
            1
        )
    }

    func testManualQuoteSelectionHoldsWithTheFullPool() {
        let count = DailyHighlightQuoteLibrary.all.count
        let selection = DailyHighlightQuoteRotation.ManualSelection(index: count - 1, tick: 50)

        for tick in [50, 51] {
            XCTAssertEqual(
                DailyHighlightQuoteRotation.displayedIndex(
                    quoteCount: count,
                    autoRotates: true,
                    manualSelection: selection,
                    currentTick: tick
                ),
                count - 1
            )
        }
        XCTAssertEqual(
            DailyHighlightQuoteRotation.displayedIndex(
                quoteCount: count,
                autoRotates: true,
                manualSelection: selection,
                currentTick: 52
            ),
            52 % count
        )
    }

    func testSwipeLeftAdvancesAndSwipeRightGoesBack() {
        let count = DailyHighlightQuoteLibrary.all.count
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: 0, quoteCount: count, dragWidth: -60), 1)
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: 5, quoteCount: count, dragWidth: 60), 4)
    }

    func testSwipeWrapsAroundThePool() {
        let count = DailyHighlightQuoteLibrary.all.count
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: count - 1, quoteCount: count, dragWidth: -40), 0)
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: 0, quoteCount: count, dragWidth: 40), count - 1)
    }

    func testSwipeWithNoDragKeepsTheCurrentQuote() {
        let count = DailyHighlightQuoteLibrary.all.count
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: 7, quoteCount: count, dragWidth: 0), 7)
        XCTAssertEqual(DailyHighlightQuoteRotation.indexAfterSwipe(from: 0, quoteCount: 0, dragWidth: -50), 0)
    }

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

    private func lift(name: String = "Bench Press") -> Exercise {
        Exercise(name: name, category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func entry(
        _ exercise: Exercise,
        dayOffset: Int,
        hour: Int,
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .meters,
        duration: Int? = nil
    ) -> SetEntry {
        let performedAt = date(dayOffset: dayOffset, hour: hour, minute: 0)
        return SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: weight,
            weightUnit: unit,
            reps: reps,
            distance: distance,
            distanceUnit: distanceUnit,
            durationSeconds: duration,
            restAfterSeconds: exercise.defaultRestSeconds,
            createdAt: performedAt,
            updatedAt: performedAt
        )
    }

    private func date(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        second: Int = 0
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) ?? day
    }
}
