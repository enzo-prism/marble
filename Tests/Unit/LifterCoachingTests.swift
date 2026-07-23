import XCTest
@testable import marble

final class LifterCoachingTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    private func bench() -> Exercise {
        Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
    }

    private func day(_ daysAgo: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func set(
        _ exercise: Exercise,
        daysAgo: Int,
        weight: Double,
        unit: WeightUnit = .lb,
        reps: Int,
        difficulty: Int = 8,
        minute: Int = 0
    ) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: day(daysAgo, minute: minute),
            weight: weight,
            weightUnit: unit,
            reps: reps,
            difficulty: difficulty,
            restAfterSeconds: 90
        )
    }

    // MARK: - Trend math

    func testTrendPercentChangeOnLinearRise() {
        let pct = LifterCoaching.trendPercentChange(values: [100, 102, 104, 106])
        XCTAssertEqual(pct, 2.0 * 3 / 103 * 100, accuracy: 0.001)
    }

    func testTrendPercentChangeFlatIsZero() {
        XCTAssertEqual(LifterCoaching.trendPercentChange(values: [100, 100, 100, 100]), 0, accuracy: 0.0001)
    }

    // MARK: - Progression verdicts

    func testRisingLiftReadsProgressing() {
        let exercise = bench()
        let history = (0..<5).map { index in
            set(exercise, daysAgo: (4 - index) * 3, weight: 100 + Double(index) * 5, reps: 5)
        }

        let assessment = LifterCoaching.progressionAssessment(history: history, exercise: exercise, calendar: calendar)

        XCTAssertEqual(assessment?.verdict, .progressing)
        XCTAssertEqual(assessment?.exposures.count, 5)
        XCTAssertGreaterThan(assessment?.percentChange ?? 0, LifterCoaching.progressingThresholdPercent)
    }

    func testFlatLiftAtEqualEffortReadsAdapted() {
        let exercise = bench()
        let history = (0..<5).map { index in
            set(exercise, daysAgo: (4 - index) * 3, weight: 185, reps: 5, difficulty: 8)
        }

        let assessment = LifterCoaching.progressionAssessment(history: history, exercise: exercise, calendar: calendar)

        XCTAssertEqual(assessment?.verdict, .adapted)
    }

    func testFlatLiftWithDroppedEffortReadsHoldingNotAdapted() {
        let exercise = bench()
        // Flat e1RM but the recent sessions were much easier — consolidating,
        // not stuck.
        let history = (0..<6).map { index in
            set(exercise, daysAgo: (5 - index) * 3, weight: 185, reps: 5, difficulty: index < 3 ? 9 : 6)
        }

        let assessment = LifterCoaching.progressionAssessment(history: history, exercise: exercise, calendar: calendar)

        XCTAssertEqual(assessment?.verdict, .holding)
    }

    func testFewExposuresReadBuilding() {
        let exercise = bench()
        let history = (0..<3).map { index in
            set(exercise, daysAgo: (2 - index) * 3, weight: 100 + Double(index) * 10, reps: 5)
        }

        let assessment = LifterCoaching.progressionAssessment(history: history, exercise: exercise, calendar: calendar)

        XCTAssertEqual(assessment?.verdict, .building)
    }

    func testExposuresCapAtProgressionWindow() {
        let exercise = bench()
        let history = (0..<12).map { index in
            set(exercise, daysAgo: (11 - index) * 2, weight: 100 + Double(index), reps: 5)
        }

        let assessment = LifterCoaching.progressionAssessment(history: history, exercise: exercise, calendar: calendar)

        XCTAssertEqual(assessment?.exposures.count, LifterCoaching.progressionWindow)
    }

    func testTopLiftsRankByRangeSetCount() {
        let benchPress = bench()
        let squat = Exercise(name: "Squat", category: .quads, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        var history: [SetEntry] = []
        for index in 0..<6 { history.append(set(squat, daysAgo: index * 2, weight: 225, reps: 5, minute: index)) }
        for index in 0..<3 { history.append(set(benchPress, daysAgo: index * 2, weight: 135, reps: 5, minute: 30 + index)) }

        let assessments = LifterCoaching.topLiftAssessments(rangeEntries: history, history: history, calendar: calendar)

        XCTAssertEqual(assessments.first?.exerciseName, "Squat")
        XCTAssertEqual(assessments.count, 2)
    }

    // MARK: - Double progression

    func testHintFiresWhenAllSetsTopCeilingAtManageableEffort() {
        let exercise = bench()
        let history = [
            set(exercise, daysAgo: 0, weight: 135, reps: 8, difficulty: 8, minute: 0),
            set(exercise, daysAgo: 0, weight: 135, reps: 9, difficulty: 8, minute: 5),
            set(exercise, daysAgo: 0, weight: 135, reps: 8, difficulty: 7, minute: 10)
        ]

        let hint = LifterCoaching.doubleProgressionHint(history: history, exercise: exercise, calendar: calendar)

        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.evidence.contains("All 3 sets") ?? false)
        XCTAssertTrue(hint?.suggestion.contains("140") ?? false, "135 lb + 2.5% rounded to plate math is 140 lb, got: \(hint?.suggestion ?? "nil")")
    }

    func testHintStaysQuietBelowRepCeiling() {
        let exercise = bench()
        let history = [
            set(exercise, daysAgo: 0, weight: 135, reps: 8, minute: 0),
            set(exercise, daysAgo: 0, weight: 135, reps: 6, minute: 5)
        ]

        XCTAssertNil(LifterCoaching.doubleProgressionHint(history: history, exercise: exercise, calendar: calendar))
    }

    func testHintStaysQuietOnGrindingEffort() {
        let exercise = bench()
        let history = [
            set(exercise, daysAgo: 0, weight: 135, reps: 8, difficulty: 10, minute: 0),
            set(exercise, daysAgo: 0, weight: 135, reps: 8, difficulty: 9, minute: 5)
        ]

        XCTAssertNil(LifterCoaching.doubleProgressionHint(history: history, exercise: exercise, calendar: calendar))
    }

    func testHintStaysQuietOnMixedWeights() {
        let exercise = bench()
        let history = [
            set(exercise, daysAgo: 0, weight: 135, reps: 8, minute: 0),
            set(exercise, daysAgo: 0, weight: 140, reps: 8, minute: 5)
        ]

        XCTAssertNil(LifterCoaching.doubleProgressionHint(history: history, exercise: exercise, calendar: calendar))
    }

    func testNextLoadSuggestionRoundsToPlateMath() {
        XCTAssertEqual(LifterCoaching.nextLoadSuggestion(after: 135, unit: .lb), 140.0, accuracy: 0.0001)
        XCTAssertEqual(LifterCoaching.nextLoadSuggestion(after: 100, unit: .kg), 102.5, accuracy: 0.0001)
        // Tiny loads still move by at least one plate step.
        XCTAssertEqual(LifterCoaching.nextLoadSuggestion(after: 20, unit: .lb), 22.5, accuracy: 0.0001)
    }

    // MARK: - Rep records

    func testRepRecordsPickHeaviestPerRepCountAcrossUnits() {
        let exercise = bench()
        let history = [
            set(exercise, daysAgo: 10, weight: 225, unit: .lb, reps: 5, minute: 0),
            // 105 kg ≈ 231 lb — heavier than 225 lb at the same rep count.
            set(exercise, daysAgo: 5, weight: 105, unit: .kg, reps: 5, minute: 0),
            set(exercise, daysAgo: 3, weight: 185, unit: .lb, reps: 8, minute: 0),
            // Above the 12-rep cap: excluded entirely.
            set(exercise, daysAgo: 1, weight: 95, unit: .lb, reps: 15, minute: 0)
        ]

        let records = LifterCoaching.repRecords(history: history, exercise: exercise)

        XCTAssertEqual(records.map(\.reps), [5, 8])
        XCTAssertEqual(records.first?.weightText.contains("105") ?? false, true, "The kg set should win at 5 reps")
    }

    // MARK: - PR feed

    func testPREventsExcludeBaselinesAndEarlySessions() {
        let exercise = bench()
        var history: [SetEntry] = []
        // Five sessions, each heavier — the journal would badge every one,
        // but the feed suppresses the baseline and the first three sessions.
        for index in 0..<5 {
            history.append(set(exercise, daysAgo: 20 - index * 4, weight: 100 + Double(index) * 10, reps: 5))
        }

        let events = LifterCoaching.prEvents(history: history, rangeStart: nil, selectedExerciseID: nil, calendar: calendar)

        XCTAssertEqual(events.count, 2, "Only sessions 4 and 5 should feed the feed")
        XCTAssertEqual(events.first?.setSummary.contains("140") ?? false, true, "Newest first")
    }

    func testPREventsRespectRangeStartAndExerciseFilter() {
        let benchPress = bench()
        let squat = Exercise(name: "Squat", category: .quads, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        var history: [SetEntry] = []
        for index in 0..<5 {
            history.append(set(benchPress, daysAgo: 40 - index * 8, weight: 100 + Double(index) * 10, reps: 5))
            history.append(set(squat, daysAgo: 40 - index * 8, weight: 200 + Double(index) * 10, reps: 5, minute: 30))
        }

        let all = LifterCoaching.prEvents(history: history, rangeStart: nil, selectedExerciseID: nil, calendar: calendar)
        let benchOnly = LifterCoaching.prEvents(history: history, rangeStart: nil, selectedExerciseID: benchPress.id, calendar: calendar)
        let recent = LifterCoaching.prEvents(history: history, rangeStart: day(10), selectedExerciseID: nil, calendar: calendar)
        let filteredBench = LifterCoaching.filteredPREvents(all, rangeStart: nil, selectedExerciseID: benchPress.id)
        let filteredRecent = LifterCoaching.filteredPREvents(all, rangeStart: day(10), selectedExerciseID: nil)

        XCTAssertEqual(all.count, 4)
        XCTAssertTrue(benchOnly.allSatisfy { $0.exerciseName == "Bench Press" })
        XCTAssertTrue(recent.allSatisfy { $0.date >= day(10) })
        XCTAssertEqual(filteredBench, benchOnly)
        XCTAssertEqual(filteredRecent, recent)
    }

    func testPREventsNormalizeUnits() {
        let exercise = bench()
        var history: [SetEntry] = []
        for index in 0..<4 {
            history.append(set(exercise, daysAgo: 20 - index * 4, weight: 100, unit: .kg, reps: 5))
        }
        // 210 lb ≈ 95 kg — lighter than 100 kg despite the bigger number.
        history.append(set(exercise, daysAgo: 2, weight: 210, unit: .lb, reps: 5))

        let events = LifterCoaching.prEvents(history: history, rangeStart: nil, selectedExerciseID: nil, calendar: calendar)

        XCTAssertTrue(events.allSatisfy { !$0.badge.contains(.weight) }, "A lighter lb set must not badge as a weight PR over a kg set")
    }

    // MARK: - Muscle coverage

    func testCoverageCountsFractionalIndirectSets() {
        let benchPress = bench()
        let entries = (0..<10).map { index in
            set(benchPress, daysAgo: index % 7, weight: 135, reps: 8, minute: index)
        }

        let coverage = LifterCoaching.muscleGroupCoverage(
            rangeEntries: entries,
            history: entries,
            weekCount: 1,
            now: now,
            calendar: calendar
        )

        let chest = coverage.first { $0.category == .chest }
        let triceps = coverage.first { $0.category == .triceps }
        XCTAssertEqual(chest?.directSets, 10)
        XCTAssertEqual(chest?.setsPerWeek ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(chest?.band, .inRange)
        XCTAssertEqual(triceps?.indirectSets ?? 0, 5.0, accuracy: 0.001, "10 pressing sets count 0.5 each toward triceps")
        XCTAssertEqual(triceps?.band, .below)
    }

    func testCoverageIncludesRecentlyTrainedGroupsWithZeroRangeSets() {
        let benchPress = bench()
        let squat = Exercise(name: "Squat", category: .quads, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let rangeEntries = [set(benchPress, daysAgo: 1, weight: 135, reps: 8)]
        let history = rangeEntries + [set(squat, daysAgo: 12, weight: 225, reps: 5)]

        let coverage = LifterCoaching.muscleGroupCoverage(
            rangeEntries: rangeEntries,
            history: history,
            weekCount: 1,
            now: now,
            calendar: calendar
        )

        let quads = coverage.first { $0.category == .quads }
        XCTAssertNotNil(quads, "A muscle trained 12 days ago should appear as a zero-row nudge")
        XCTAssertEqual(quads?.setsPerWeek ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(quads?.lastTrainedDaysAgo, 12)
    }

    func testCoverageFlagsHighVolume() {
        let benchPress = bench()
        let entries = (0..<25).map { index in
            set(benchPress, daysAgo: index % 7, weight: 135, reps: 8, minute: index)
        }

        let coverage = LifterCoaching.muscleGroupCoverage(
            rangeEntries: entries,
            history: entries,
            weekCount: 1,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(coverage.first { $0.category == .chest }?.band, .high)
    }
}
