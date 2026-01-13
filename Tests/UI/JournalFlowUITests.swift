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
        let openLatest = app.buttons["Journal.TestOpenLatest"]
        waitFor(openLatest, timeout: 8)

        forceTap(openLatest)
        if !app.navigationBars["Set Details"].waitForExistence(timeout: 3) {
            forceTap(openLatest)
        }
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

        let listAfterEdit = waitForIdentifier("Journal.List", timeout: 8)
        let openLatestAgain = app.buttons["Journal.TestOpenLatest"]
        waitFor(openLatestAgain, timeout: 8)
        forceTap(openLatestAgain)
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

        let updatedRows = setRows(in: listAfterEdit)
        let updatedRow = updatedRows.element(boundBy: 0)
        waitFor(updatedRow, timeout: 8)
        updatedRow.swipeRight()
        let duplicateButton = app.buttons["Duplicate"]
        waitFor(duplicateButton)
        duplicateButton.tap()

        let listAfterDuplicate = waitForIdentifier("Journal.List", timeout: 8)
        let duplicatedRows = setRows(in: listAfterDuplicate)
        let secondRow = duplicatedRows.element(boundBy: 1)
        waitFor(secondRow, timeout: 8)

        updatedRow.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        waitFor(deleteButton)
        deleteButton.tap()

        let toast = waitForIdentifier("Toast", timeout: 5)
        let undoButton = app.buttons["Undo"]
        if undoButton.exists {
            undoButton.tap()
            waitFor(app.tables.cells.element(boundBy: 1))
        }
    }

    func testSaveAndStartRest() {
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

        app.buttons["RPEPicker.8"].tap()
        app.buttons["RestPicker.90"].tap()

        let saveStartRest = app.buttons["AddSet.SaveStartRest"]
        var attempts = 0
        while !saveStartRest.exists, attempts < 3 {
            app.swipeUp()
            attempts += 1
        }
        waitFor(saveStartRest)
        if !saveStartRest.isHittable {
            app.swipeUp()
        }
        saveStartRest.tap()

        let restDone = app.buttons["RestTimer.Done"]
        waitFor(restDone, timeout: 6)
        restDone.tap()

        dismissSheet()
        waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

        let list = waitForIdentifier("Journal.List", timeout: 8)
        let rows = setRows(in: list)
        XCTAssertTrue(rows.element(boundBy: 0).exists)
    }

    func testSaveAddAnotherDoesNotCrash() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()
        selectExercise(identifier: "BenchPress")

        let weightField = textInput("AddSet.Weight")
        waitFor(weightField)
        clearAndType(weightField, text: "135")

        let repsField = textInput("AddSet.Reps")
        waitFor(repsField)
        clearAndType(repsField, text: "8")

        app.buttons["RPEPicker.8"].tap()
        app.buttons["RestPicker.60"].tap()

        let saveAddAnother = app.buttons["AddSet.SaveAddAnother"]
        waitFor(saveAddAnother)
        if !saveAddAnother.isHittable {
            app.swipeUp()
        }
        saveAddAnother.tap()

        waitFor(app.navigationBars["Log Set"])
        let saveButton = app.buttons["AddSet.Save"]
        waitFor(saveButton)
        if !saveButton.isHittable {
            app.swipeUp()
        }
        saveButton.tap()

        let missingExerciseAlert = app.alerts["Exercise Removed"]
        if missingExerciseAlert.waitForExistence(timeout: 1) {
            takeScreenshot("AddSet_MissingExercise")
            XCTFail("Exercise removed alert appeared after save.")
        }

        let saveErrorAlert = app.alerts["Unable to Save"]
        if saveErrorAlert.waitForExistence(timeout: 1) {
            takeScreenshot("AddSet_SaveError")
            XCTFail("Save error alert appeared after save.")
        }

        waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

        let list = waitForIdentifier("Journal.List", timeout: 8)
        let rows = setRows(in: list)
        XCTAssertTrue(rows.element(boundBy: 0).exists)
    }

    func testAddDurationSetDoesNotCrash() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()
        let picker = app.buttons["AddSet.ExercisePicker"]
        waitFor(picker)
        picker.tap()

        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 2) {
            searchField.tap()
            searchField.typeText("Plank")
        }

        let plankRow = app.buttons.matching(identifier: "ExercisePicker.Row.Plank").firstMatch
        waitFor(plankRow)
        plankRow.tap()

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
        XCTAssertTrue(rows.element(boundBy: 0).exists)
    }

    func testAddSetAfterExerciseDeletionDoesNotCrash() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()

        let exercisePicker = app.buttons["AddSet.ExercisePicker"]
        waitFor(exercisePicker)
        exercisePicker.tap()

        let manage = app.buttons["ExercisePicker.Manage"]
        waitFor(manage)
        manage.tap()

        let addExercise = app.buttons["ManageExercises.Add"]
        waitFor(addExercise)
        addExercise.tap()

        let nameField = app.textFields["ExerciseEditor.Name"]
        waitFor(nameField)
        nameField.tap()
        nameField.typeText("Temp Move")

        let saveExercise = app.buttons["ExerciseEditor.Save"]
        waitFor(saveExercise)
        saveExercise.tap()

        let backFromManage = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backFromManage)
        backFromManage.tap()

        let tempRow = app.buttons["ExercisePicker.Row.TempMove"]
        waitFor(tempRow)
        tempRow.tap()

        waitFor(app.navigationBars["Log Set"])
        let exercisePickerAgain = app.buttons["AddSet.ExercisePicker"]
        waitFor(exercisePickerAgain)
        exercisePickerAgain.tap()
        waitFor(manage)
        manage.tap()

        let manageList = waitForIdentifier("ManageExercises.List", timeout: 6)
        let tempCell = manageList.cells.containing(.staticText, identifier: "Temp Move").firstMatch
        waitFor(tempCell, timeout: 6)
        tempCell.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        waitFor(deleteButton)
        deleteButton.tap()

        let backToExercises = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backToExercises)
        backToExercises.tap()
        let backToAddSet = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backToAddSet)
        backToAddSet.tap()

        let removedAlert = app.alerts["Exercise Removed"]
        if removedAlert.waitForExistence(timeout: 3) {
            removedAlert.buttons["OK"].tap()
        }

        XCTAssertTrue(app.navigationBars["Log Set"].exists)
    }
}
