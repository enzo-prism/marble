import XCTest

final class TrendsSmokeUITests: MarbleUITestCase {
    func testTrendsChartsRender() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

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

    private func chartElement(_ identifier: String) -> XCUIElement {
        let legacyChartElement = app.otherElements[identifier]
        if legacyChartElement.exists {
            return legacyChartElement
        }
        return app.buttons[identifier]
    }
}
