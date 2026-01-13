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
        if app.navigationBars["Log Set"].exists {
            dismissSheet()
        }
        waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

        let list = waitForIdentifier("Journal.List", timeout: 8)
        let rows = setRows(in: list)
        let firstRow = rows.element(boundBy: 0)
        waitFor(firstRow, timeout: 8)

        forceTap(firstRow)
        waitFor(app.navigationBars["Set Details"], timeout: 6)
        let detailWeight = textInput("SetDetail.Weight")
        if !detailWeight.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        waitFor(detailWeight, timeout: 6)
        clearAndType(detailWeight, text: "190")

        let detailReps = textInput("SetDetail.Reps")
        if !detailReps.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        waitFor(detailReps, timeout: 6)
        clearAndType(detailReps, text: "6")

        app.buttons["RPEPicker.9"].tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backButton)
        backButton.tap()

        let updatedRow = rows.element(boundBy: 0)
        waitFor(updatedRow, timeout: 8)
        forceTap(updatedRow)
        waitFor(app.navigationBars["Set Details"], timeout: 6)
        let verifyWeight = textInput("SetDetail.Weight")
        if !verifyWeight.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        waitFor(verifyWeight, timeout: 6)
        XCTAssertEqual(verifyWeight.value as? String, "190")
        let verifyReps = textInput("SetDetail.Reps")
        if !verifyReps.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        waitFor(verifyReps, timeout: 6)
        XCTAssertEqual(verifyReps.value as? String, "6")
        let backAgain = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backAgain)
        backAgain.tap()

        updatedRow.swipeRight()
        let duplicateButton = app.buttons["Duplicate"]
        waitFor(duplicateButton)
        duplicateButton.tap()

        let secondRow = rows.element(boundBy: 1)
        waitFor(secondRow, timeout: 8)

        updatedRow.swipeLeft()
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
