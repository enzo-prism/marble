import XCTest

final class JournalFlowUITests: MarbleUITestCase {
    func testAddEditDuplicateDeleteSet() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Add a new set") {
            openAddSet()
            selectExercise(identifier: "BenchPress")

            let weightField = textInput("AddSet.Weight")
            waitFor(weightField)
            clearAndType(weightField, text: "185")
            dismissKeyboardIfPresent()

            setSliderValue("AddSet.Reps", value: 5, range: 1...20)

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)
            let logSetNav = app.navigationBars["Log Set"]
            if logSetNav.waitForExistence(timeout: 1) {
                waitForDisappearance(logSetNav, timeout: 4)
            }
            if logSetNav.exists {
                dismissSheet()
            }
            waitForDisappearance(logSetNav, timeout: 6)
            _ = waitForIdentifier("Journal.List", timeout: 8)
        }

        step("Edit the latest set") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            let latestRow = rows.element(boundBy: 0)
            waitFor(latestRow, timeout: 8)
            forceTap(latestRow)
            if !app.navigationBars["Set Details"].waitForExistence(timeout: 3) {
                forceTap(latestRow)
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

            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            waitFor(backButton)
            backButton.tap()

            _ = waitForIdentifier("Journal.List", timeout: 8)
            let updatedList = waitForIdentifier("Journal.List", timeout: 8)
            let updatedRows = setRows(in: updatedList)
            let latestUpdatedRow = updatedRows.element(boundBy: 0)
            waitFor(latestUpdatedRow, timeout: 8)
            forceTap(latestUpdatedRow)
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
        }

        step("Duplicate the latest set") {
            let listAfterEdit = waitForIdentifier("Journal.List", timeout: 8)
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
        }

        step("Delete and undo") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            let firstRow = rows.element(boundBy: 0)
            waitFor(firstRow, timeout: 8)
            firstRow.swipeLeft()
            let deleteButton = app.buttons["Delete"]
            waitFor(deleteButton)
            deleteButton.tap()

            _ = waitForIdentifier("Toast", timeout: 5)
            let undoButton = app.buttons["Undo"]
            if undoButton.exists {
                undoButton.tap()
                let listAfterUndo = waitForIdentifier("Journal.List", timeout: 8)
                let rowsAfterUndo = setRows(in: listAfterUndo)
                XCTAssertTrue(rowsAfterUndo.element(boundBy: 1).waitForExistence(timeout: 6))
            }
        }
    }

    func testAddDurationSetDoesNotCrash() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Add a duration set") {
            openAddSet()
            selectExercise(identifier: "Plank")

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)

            if app.navigationBars["Log Set"].exists {
                dismissSheet()
            }
            waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            XCTAssertTrue(rows.element(boundBy: 0).exists)
        }
    }

    func testAddSetAfterExerciseDeletionDoesNotCrash() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Create and delete an exercise while Add Set is open") {
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

            let bodyweightTemplate = app.buttons["ExerciseEditor.Template.bodyweight"]
            scrollToElement(bodyweightTemplate, in: app.tables.firstMatch)
            waitFor(bodyweightTemplate)
            forceTap(bodyweightTemplate)

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            saveExercise.tap()

            waitFor(app.navigationBars["Log Set"])
            XCTAssertEqual(exercisePicker.value as? String, "Temp Move")
            let exercisePickerAgain = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePickerAgain)
            exercisePickerAgain.tap()
            waitFor(manage)
            manage.tap()

            let manageList = waitForIdentifier("ManageExercises.List", timeout: 6)
            let tempCell = manageList.cells.containing(.staticText, identifier: "Temp Move").firstMatch
            scrollToElement(tempCell, in: manageList)
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

    func testCreateExerciseFromPickerSearchAndUseItImmediately() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Create a new exercise directly from the picker search flow") {
            openAddSet()

            let exercisePicker = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePicker)
            exercisePicker.tap()

            let searchField = app.searchFields.firstMatch
            waitFor(searchField, timeout: 4)
            searchField.tap()
            searchField.typeText("Ring Row")

            let createButton = app.buttons["ExercisePicker.CreateFromSearch"]
            waitFor(createButton)
            forceTap(createButton)

            let nameField = app.textFields["ExerciseEditor.Name"]
            waitFor(nameField)
            XCTAssertEqual(nameField.value as? String, "Ring Row")

            let iconMode = app.segmentedControls["ExerciseEditor.IconMode"]
            waitFor(iconMode)
            iconMode.buttons["Emoji"].tap()

            let firstEmojiSuggestion = app.buttons["ExerciseEditor.EmojiSuggestion.0"]
            waitFor(firstEmojiSuggestion)
            forceTap(firstEmojiSuggestion)

            let weightedBodyweightTemplate = app.buttons["ExerciseEditor.Template.weightedBodyweight"]
            scrollToElement(weightedBodyweightTemplate, in: app.tables.firstMatch)
            waitFor(weightedBodyweightTemplate)
            forceTap(weightedBodyweightTemplate)

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            forceTap(saveExercise)
        }

        step("Use the new exercise with the expected logging fields") {
            waitFor(app.navigationBars["Log Set"], timeout: 6)

            let exercisePicker = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePicker)
            XCTAssertEqual(exercisePicker.value as? String, "Ring Row")

            let addedLoadToggle = app.switches["AddSet.AddedLoad"]
            waitFor(addedLoadToggle)
            let repsSlider = app.sliders["AddSet.Reps"]
            if repsSlider.waitForExistence(timeout: 2) {
                setSliderValue("AddSet.Reps", value: 8, range: 1...20)
            }

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)
            if app.navigationBars["Log Set"].exists {
                dismissSheet()
            }
            waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

            let list = waitForIdentifier("Journal.List", timeout: 8)
            XCTAssertTrue(setRows(in: list).element(boundBy: 0).exists)
        }
    }

    func testEditExistingExerciseCanSwitchToEmojiIcon() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "populated")
            navigateToTab(.journal)
        }

        step("Open Bench Press in exercise management") {
            openAddSet()

            let exercisePicker = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePicker)
            exercisePicker.tap()

            let manage = app.buttons["ExercisePicker.Manage"]
            waitFor(manage)
            manage.tap()

            let manageList = waitForIdentifier("ManageExercises.List", timeout: 6)
            let benchPressRow = app.buttons["ManageExercises.Row.BenchPress"]
            scrollToElement(benchPressRow, in: manageList)
            waitFor(benchPressRow, timeout: 6)
            forceTap(benchPressRow)
        }

        step("Change the icon to an emoji and save") {
            waitFor(app.navigationBars["Edit Exercise"], timeout: 6)

            let iconMode = app.segmentedControls["ExerciseEditor.IconMode"]
            waitFor(iconMode)
            iconMode.buttons["Emoji"].tap()

            let firstEmojiSuggestion = app.buttons["ExerciseEditor.EmojiSuggestion.0"]
            waitFor(firstEmojiSuggestion)
            forceTap(firstEmojiSuggestion)

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            forceTap(saveExercise)
        }

        step("Reopen the exercise and confirm the emoji choice persisted") {
            let manageList = waitForIdentifier("ManageExercises.List", timeout: 6)
            let benchPressRow = app.buttons["ManageExercises.Row.BenchPress"]
            scrollToElement(benchPressRow, in: manageList)
            waitFor(benchPressRow, timeout: 6)
            forceTap(benchPressRow)

            waitFor(app.navigationBars["Edit Exercise"], timeout: 6)

            let customEmojiField = app.textFields["ExerciseEditor.CustomEmoji"]
            waitFor(customEmojiField)
            XCTAssertEqual(customEmojiField.value as? String, "🏋️")
        }
    }

    func testDualDumbbellExerciseStoresTotalLoadButKeepsPerHandEditing() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Create a dual dumbbell exercise from the picker") {
            openAddSet()

            let exercisePicker = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePicker)
            exercisePicker.tap()

            let searchField = app.searchFields.firstMatch
            waitFor(searchField, timeout: 4)
            searchField.tap()
            searchField.typeText("DB Incline Press")

            let createButton = app.buttons["ExercisePicker.CreateFromSearch"]
            waitFor(createButton)
            forceTap(createButton)

            let dualDumbbellTemplate = app.buttons["ExerciseEditor.Template.dualDumbbell"]
            scrollToElement(dualDumbbellTemplate, in: app.tables.firstMatch)
            waitFor(dualDumbbellTemplate)
            forceTap(dualDumbbellTemplate)

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            forceTap(saveExercise)
        }

        step("Log a set using one dumbbell weight") {
            waitFor(app.navigationBars["Log Set"], timeout: 6)

            let weightField = textInput("AddSet.Weight")
            waitFor(weightField)
            clearAndType(weightField, text: "25")
            dismissKeyboardIfPresent()

            setSliderValue("AddSet.Reps", value: 8, range: 1...20)

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)
            waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)
        }

        step("Confirm the journal and edit flow reflect per-hand input correctly") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            let latestRow = rows.element(boundBy: 0)
            waitFor(latestRow, timeout: 8)
            XCTAssertTrue((latestRow.label as String).contains("50 lb total"))

            forceTap(latestRow)
            waitFor(app.navigationBars["Set Details"], timeout: 6)

            let detailWeight = textInput("SetDetail.Weight")
            waitFor(detailWeight)
            XCTAssertEqual(detailWeight.value as? String, "25")
        }
    }

    func testSprintExerciseShowsDistanceAndDurationLogging() {
        step("Launch and open Journal tab") {
            launchApp(fixtureMode: "empty")
            navigateToTab(.journal)
        }

        step("Create a sprint-style exercise from the picker") {
            openAddSet()

            let exercisePicker = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePicker)
            exercisePicker.tap()

            let searchField = app.searchFields.firstMatch
            waitFor(searchField, timeout: 4)
            searchField.tap()
            searchField.typeText("Track Sprint")

            let createButton = app.buttons["ExercisePicker.CreateFromSearch"]
            waitFor(createButton)
            forceTap(createButton)

            let sprintTemplate = app.buttons["ExerciseEditor.Template.sprint"]
            scrollToElement(sprintTemplate, in: app.tables.firstMatch)
            waitFor(sprintTemplate)
            forceTap(sprintTemplate)

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            forceTap(saveExercise)
        }

        step("Log a sprint with distance and time") {
            waitFor(app.navigationBars["Log Set"], timeout: 6)

            let distanceField = textInput("AddSet.Distance")
            waitFor(distanceField)
            clearAndType(distanceField, text: "100")
            dismissKeyboardIfPresent()

            let durationControl = app.otherElements["AddSet.Duration"]
            waitFor(durationControl)

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)
            waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)
        }

        step("Confirm the saved set still exposes distance and duration") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            let latestRow = rows.element(boundBy: 0)
            waitFor(latestRow, timeout: 8)
            XCTAssertTrue((latestRow.label as String).contains("100 m"))

            forceTap(latestRow)
            waitFor(app.navigationBars["Set Details"], timeout: 6)

            let detailDistance = textInput("SetDetail.Distance")
            waitFor(detailDistance)
            XCTAssertEqual(detailDistance.value as? String, "100")
            XCTAssertTrue(app.otherElements["SetDetail.Duration"].waitForExistence(timeout: 2))
        }
    }

}
