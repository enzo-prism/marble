import XCTest

final class TrendsSmokeUITests: MarbleUITestCase {
    func testDailyHighlightsAppearOnlyInTheCelebrationWindowAndOpenSettings() {
        launchApp(
            fixtureMode: "populated",
            nowISO8601: MarbleUITestCase.fixtureNowISO8601(hour: 21)
        )
        navigateToTab(.trends)

        let highlights = waitForIdentifier("Trends.DailyHighlights", timeout: 10)
        XCTAssertTrue(highlights.exists)
        waitForIdentifier("Trends.DailyHighlights.Achievement.0", timeout: 8)

        let quote = app.buttons["Trends.DailyHighlights.Quote"]
        waitFor(quote, timeout: 8)
        XCTAssertTrue(quote.label.contains("Daily motivation"))
        XCTAssertTrue((quote.value as? String)?.contains("Quote 1 of 3") == true)

        let firstQuote = quote.value as? String
        forceTap(quote)
        let quoteChanged = expectation(
            for: NSPredicate(format: "value != %@", firstQuote ?? ""),
            evaluatedWith: quote
        )
        wait(for: [quoteChanged], timeout: 3)

        let removedShare = app.descendants(matching: .any)
            .matching(identifier: "Trends.DailyHighlights.Share")
            .firstMatch
        XCTAssertFalse(removedShare.exists)

        let customize = waitForIdentifier("Trends.DailyHighlights.Customize", timeout: 8)
        forceTap(customize)
        waitForIdentifier("DailyHighlights.Enabled", timeout: 8)
        waitForIdentifier("DailyHighlights.Start", timeout: 8)
        waitForIdentifier("DailyHighlights.End", timeout: 8)
        forceTap(waitForIdentifier("DailyHighlights.Done", timeout: 8))

        launchApp(
            fixtureMode: "populated",
            nowISO8601: MarbleUITestCase.fixtureNowISO8601(hour: 12)
        )
        navigateToTab(.trends)

        let hiddenHighlights = app.descendants(matching: .any)
            .matching(identifier: "Trends.DailyHighlights")
            .firstMatch
        XCTAssertFalse(hiddenHighlights.waitForExistence(timeout: 3))
    }

    func testDetailsToggleSupportsLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated"
        )
        navigateToTab(.trends)

        let scrollView = app.scrollViews["Trends.Scroll"]
        let toggle = app.descendants(matching: .any).matching(identifier: "Trends.Details.Toggle").firstMatch
        scrollToElement(toggle, in: scrollView)
        waitFor(toggle, timeout: 8)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertGreaterThan(toggle.frame.height, 80, "The detailed analytics action should grow to fit its wrapped label")
    }

    func testTrendsChartsRender() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)
        revealDetailedTrends()

        assertTrendSummaryMetrics()

        let consistencyChart = chartElement("Trends.ConsistencyChart")
        waitFor(consistencyChart)
        let volumeChart = chartElement("Trends.VolumeChart")
        waitFor(volumeChart)

        let supplementsChart = chartElement("Trends.SupplementsChart")
        if !supplementsChart.exists {
            let scrollView = app.scrollViews["Trends.Scroll"]
            for _ in 0..<3 {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
                if supplementsChart.exists {
                    break
                }
            }
        }
        waitFor(supplementsChart)

        // The lifter-analytics sections sit between the volume chart and the
        // supplements section; by the time the scroll reached supplements they
        // have rendered at least once, so existence checks are stable here.
        assertChartReachable("Trends.MuscleGroupsChart")
        assertChartReachable("Trends.RepRangesChart")
        assertChartReachable("Trends.EffortChart")

        let prCards = app.otherElements["Trends.PRCards"]
        if !prCards.exists {
            let scrollView = app.scrollViews["Trends.Scroll"]
            for _ in 0..<2 {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
                if prCards.exists {
                    break
                }
            }
        }
        waitFor(prCards, timeout: 6)

        let rangePicker = app.segmentedControls["Trends.Range"]
        if rangePicker.exists {
            let sevenDay = rangePicker.buttons["7D"]
            waitFor(sevenDay)
            sevenDay.tap()
            XCTAssertTrue(sevenDay.isSelected)
        }

        let exerciseFilterButton = app.buttons["Trends.ExerciseSearchButton"]
        waitFor(exerciseFilterButton)
        forceTap(exerciseFilterButton)

        let searchField = app.searchFields["Search exercises"]
        waitFor(searchField)
        searchField.tap()
        searchField.typeText("Bench")

        let benchOption = waitForIdentifier("Trends.ExerciseSearch.Row.BenchPress", timeout: 6)
        forceTap(benchOption)
        XCTAssertEqual(exerciseFilterButton.value as? String, "Bench Press")
        XCTAssertTrue(chartElement("Trends.ConsistencyChart").exists)

        // With a weight+reps exercise selected, the estimated-1RM section
        // renders below Progress (fixture Bench Press sets are ≤ 12 reps).
        assertChartReachable("Trends.StrengthChart")

        forceTap(exerciseFilterButton)
        let allExercisesOption = waitForIdentifier("Trends.ExerciseSearch.All", timeout: 6)
        forceTap(allExercisesOption)
        XCTAssertEqual(exerciseFilterButton.value as? String, "All Exercises")

        let supplementPicker = app.buttons["Trends.SupplementFilter"]
        if supplementPicker.exists {
            supplementPicker.tap()
            let creatineOption = app.buttons["Creatine"].firstMatch
            if creatineOption.exists {
                creatineOption.tap()
            }
            let pickerValue = supplementPicker.value as? String
            XCTAssertEqual(pickerValue, "Creatine")
        }

        XCTAssertTrue(chartElement("Trends.ConsistencyChart").exists)
    }

    private func assertTrendSummaryMetrics(file: StaticString = #file, line: UInt = #line) {
        let summary = waitForIdentifier("Trends.Summary", timeout: 8, file: file, line: line)
        let sets = waitForIdentifier("Trends.SummaryMetric.Sets", timeout: 6, file: file, line: line)
        let bestWeek = waitForIdentifier("Trends.SummaryMetric.BestWeek", timeout: 6, file: file, line: line)
        let supplements = waitForIdentifier("Trends.SummaryMetric.Supplements", timeout: 6, file: file, line: line)

        XCTAssertTrue(sets.label.contains("Sets"), file: file, line: line)
        XCTAssertTrue(bestWeek.label.contains("Best Week"), file: file, line: line)
        XCTAssertTrue(supplements.label.contains("Supplements"), file: file, line: line)
        XCTAssertFalse(supplements.label.contains("-"), file: file, line: line)
        XCTAssertGreaterThanOrEqual(supplements.frame.minX, summary.frame.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(supplements.frame.maxX, summary.frame.maxX + 1, file: file, line: line)
    }

    private func chartElement(_ identifier: String) -> XCUIElement {
        let legacyChartElement = app.otherElements[identifier]
        if legacyChartElement.exists {
            return legacyChartElement
        }
        return app.buttons[identifier]
    }

    /// Finds a chart anywhere in the hierarchy, scrolling down a few times if
    /// it hasn't been materialized yet.
    private func assertChartReachable(_ identifier: String, file: StaticString = #file, line: UInt = #line) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if !element.exists {
            let scrollView = app.scrollViews["Trends.Scroll"]
            for _ in 0..<4 {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
                if element.exists {
                    break
                }
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 6), "Missing chart \(identifier)", file: file, line: line)
    }
}
