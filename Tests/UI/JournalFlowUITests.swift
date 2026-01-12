import XCTest

final class JournalFlowUITests: MarbleUITestCase {
    func testAddEditDuplicateDeleteSet() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()
        selectExercise(identifier: "BenchPress")

        let weightField = textInput("AddSet.Weight")
        waitFor(weightField)
        clearAndType(weightField, text: "185")

        let repsField = textInput("AddSet.Reps")
        waitFor(repsField)
        clearAndType(repsField, text: "5")

        app.buttons["RPEPicker.9"].tap()
        app.buttons["RestPicker.90"].tap()

        let saveButton = app.buttons["AddSet.Save"]
        waitFor(saveButton)
        if !saveButton.isHittable {
            app.swipeUp()
        }
        saveButton.tap()

        let list = waitForIdentifier("Journal.List", timeout: 8)
        let rows = setRows(in: list)
        let firstRow = rows.element(boundBy: 0)
        waitFor(firstRow, timeout: 8)
        XCTAssertTrue(firstRow.label.contains("Bench Press"))

        firstRow.tap()
        let detailWeight = textInput("SetDetail.Weight")
        waitFor(detailWeight)
        clearAndType(detailWeight, text: "190")

        let detailReps = textInput("SetDetail.Reps")
        waitFor(detailReps)
        clearAndType(detailReps, text: "6")

        app.buttons["RPEPicker.9"].tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backButton)
        backButton.tap()

        let refreshedRow = rows.element(boundBy: 0)
        waitFor(refreshedRow, timeout: 8)
        XCTAssertTrue(refreshedRow.label.contains("190 lb × 6"))

        let updatedFirstRow = rows.element(boundBy: 0)
        waitFor(updatedFirstRow, timeout: 8)
        updatedFirstRow.swipeRight()
        let duplicateButton = app.buttons["Duplicate"]
        waitFor(duplicateButton)
        duplicateButton.tap()

        let secondRow = rows.element(boundBy: 1)
        waitFor(secondRow, timeout: 8)

        updatedFirstRow.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        waitFor(deleteButton)
        deleteButton.tap()

        let toast = waitForIdentifier("Toast", timeout: 5)
        let undoButton = app.buttons["Undo"]
        if undoButton.exists {
            undoButton.tap()
            waitFor(list.cells.element(boundBy: 1))
        }
    }
}
