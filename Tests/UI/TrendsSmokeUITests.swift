import XCTest

final class TrendsSmokeUITests: MarbleUITestCase {
    func testTrendsChartsRender() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.trends)

        let consistencyChart = app.otherElements["Trends.ConsistencyChart"]
        waitFor(consistencyChart)
        let volumeChart = app.otherElements["Trends.VolumeChart"]
        waitFor(volumeChart)

        let supplementsChart = app.otherElements["Trends.SupplementsChart"]
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

        let exercisePicker = app.buttons["Trends.ExerciseFilter"]
        if exercisePicker.exists {
            exercisePicker.tap()
            let benchOption = app.buttons["Bench Press"].firstMatch
            if benchOption.exists {
                benchOption.tap()
            }
            let pickerValue = exercisePicker.value as? String
            XCTAssertEqual(pickerValue, "Bench Press")
        }

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

        XCTAssertTrue(app.otherElements["Trends.ConsistencyChart"].exists)
    }
}
