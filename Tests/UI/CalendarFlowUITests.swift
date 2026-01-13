import XCTest

final class CalendarFlowUITests: MarbleUITestCase {
    func testCalendarDayPopulated() {
        launchApp(fixtureMode: "populated", calendarTestDay: "populated")
        navigateToTab(.calendar)

        selectCalendarDay("15")
        let daySheetList = waitForIdentifier("Calendar.DaySheet.List", timeout: 8)
        let benchRow = daySheetList.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Bench Press"))
            .firstMatch
        waitFor(benchRow, timeout: 8)

        benchRow.tap()

        let rpeNine = app.buttons["RPEPicker.9"]
        waitFor(rpeNine)
        rpeNine.tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backButton)
        backButton.tap()

        let updatedBenchRow = daySheetList.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Bench Press"))
            .firstMatch
        waitFor(updatedBenchRow, timeout: 8)
        XCTAssertTrue(updatedBenchRow.label.contains("RPE 9"))

        dismissSheet()
    }

    func testCalendarDayEmpty() {
        launchApp(fixtureMode: "empty", calendarTestDay: "empty")
        navigateToTab(.calendar)
        selectCalendarDay("1")
        let emptyState = app.descendants(matching: .any).matching(identifier: "Calendar.DaySheet.EmptyState").firstMatch
        waitFor(emptyState)
        let logButton = app.buttons["Calendar.DaySheet.LogSet"]
        waitFor(logButton)
    }
}
