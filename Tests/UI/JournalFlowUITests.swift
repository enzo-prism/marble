import XCTest

final class JournalFlowUITests: MarbleUITestCase {
    func testExerciseLibrarySupportsLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "empty"
        )
        navigateToTab(.journal)
        openAddSet()

        let exercisePicker = app.buttons["AddSet.ExercisePicker"]
        waitFor(exercisePicker)
        exercisePicker.tap()
        waitForIdentifier("ExercisePicker.List", timeout: 8)
        let manage = app.buttons["ExercisePicker.Manage"]
        let create = app.buttons["ExercisePicker.Create"]
        waitFor(manage)
        waitFor(create)
        XCTAssertTrue(manage.isHittable)
        XCTAssertTrue(create.isHittable)

        forceTap(create)
        waitForIdentifier("ExerciseEditor.List", timeout: 8)
        let name = app.textFields["ExerciseEditor.Name"]
        waitFor(name)
        XCTAssertTrue(name.isHittable)
    }

    func testEmptyJournalShowsStartChecklistActions() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        let checklist = waitForIdentifier("Journal.StartChecklist", timeout: 8)
        XCTAssertTrue(checklist.exists)
        _ = waitForIdentifier("Journal.StartChecklist.LogSet")
        _ = waitForIdentifier("Journal.StartChecklist.Import")
        _ = waitForIdentifier("Journal.StartChecklist.CreateSplit")
    }

    func testSaveAndNextKeepsLoggerOpen() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()
        selectExercise(identifier: "BenchPress")

        let weightField = textInput("AddSet.Weight")
        waitFor(weightField)
        clearAndType(weightField, text: "135")
        dismissKeyboardIfPresent()

        setSliderValue("AddSet.Reps", value: 5, range: 1...20)

        let saveAndNext = app.buttons["AddSet.SaveAndNext"]
        if !saveAndNext.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        forceTap(saveAndNext, timeout: 6)

        waitFor(app.navigationBars["Log Set"], timeout: 6)
        XCTAssertTrue(app.buttons["AddSet.SaveAndNext"].exists)

        dismissSheet()
        let list = waitForIdentifier("Journal.List", timeout: 8)
        XCTAssertGreaterThan(setRows(in: list).count, 0)
    }

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
            clearAndType(nameField, text: "Temp Move")

            selectExerciseTemplate("ExerciseEditor.Template.bodyweight")

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            saveExercise.tap()

            waitFor(app.navigationBars["Log Set"])
            let createdName = exercisePicker.value as? String
            XCTAssertTrue(createdName?.hasPrefix("Temp Move") == true)
            let exercisePickerAgain = app.buttons["AddSet.ExercisePicker"]
            waitFor(exercisePickerAgain)
            exercisePickerAgain.tap()
            waitFor(manage)
            manage.tap()

            let manageList = waitForIdentifier("ManageExercises.List", timeout: 6)
            let tempCell = manageList.cells.containing(.staticText, identifier: createdName ?? "Temp Move").firstMatch
            scrollToElement(tempCell, in: manageList)
            waitFor(tempCell, timeout: 6)
            forceTap(tempCell)

            let editorList = waitForIdentifier("ExerciseEditor.List", timeout: 6)
            let deleteButton = app.buttons["ExerciseEditor.Delete"]
            scrollToElement(deleteButton, in: editorList, maxSwipes: 12)
            forceTap(deleteButton)

            let confirmDelete = app.buttons.matching(identifier: "ExerciseEditor.Delete.Confirm").firstMatch
            waitFor(confirmDelete)
            forceTap(confirmDelete)

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

            selectExerciseTemplate("ExerciseEditor.Template.weightedBodyweight")

            expandExerciseEditorAdvanced()
            let iconMode = app.segmentedControls["ExerciseEditor.IconMode"]
            waitFor(iconMode)
            iconMode.buttons["Emoji"].tap()

            let firstEmojiSuggestion = app.buttons["ExerciseEditor.EmojiSuggestion.0"]
            if !firstEmojiSuggestion.waitForExistence(timeout: 8) {
                let editorList = app.descendants(matching: .any).matching(identifier: "ExerciseEditor.List").firstMatch
                let container = editorList.exists ? editorList : app.collectionViews.firstMatch
                scrollToElement(firstEmojiSuggestion, in: container, maxSwipes: 6)
            }
            waitFor(firstEmojiSuggestion, timeout: 10)
            forceTap(firstEmojiSuggestion)

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

            expandExerciseEditorAdvanced()
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

        step("Confirm the editor closes after saving the appearance change") {
            _ = waitForIdentifier("ManageExercises.List", timeout: 6)
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

            selectExerciseTemplate("ExerciseEditor.Template.dualDumbbell")

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
            if app.navigationBars["Log Set"].exists {
                dismissSheet()
            }
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

            selectExerciseTemplate("ExerciseEditor.Template.sprint")

            let rangeMode = app.buttons["Range"]
            let editorList = waitForIdentifier("ExerciseEditor.List", timeout: 6)
            scrollToElement(rangeMode, in: editorList)
            waitFor(rangeMode)
            rangeMode.tap()

            let saveExercise = app.buttons["ExerciseEditor.Save"]
            waitFor(saveExercise)
            forceTap(saveExercise)
        }

        step("Log a sprint with distance and time") {
            waitFor(app.navigationBars["Log Set"], timeout: 6)

            let prescription = app.descendants(matching: .any)
                .matching(identifier: "AddSet.Sprint.Prescription").firstMatch
            waitFor(prescription)
            let prescribedDistance = app.descendants(matching: .any)
                .matching(identifier: "AddSet.Sprint.Distance").firstMatch
            waitFor(prescribedDistance)

            let durationControl = app.otherElements["AddSet.Duration"]
            waitFor(durationControl)

            let secondsPicker = app.buttons["DurationPicker.Seconds"]
            waitFor(secondsPicker)
            secondsPicker.tap()
            let twentySeconds = app.buttons["20s"]
            waitFor(twentySeconds)
            twentySeconds.tap()

            let saveButton = revealAddSetSaveButton()
            forceTap(saveButton)
            if app.navigationBars["Log Set"].exists {
                dismissSheet()
            }
            waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)
        }

        step("Confirm the saved set still exposes distance and duration") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let rows = setRows(in: list)
            let latestRow = rows.element(boundBy: 0)
            waitFor(latestRow, timeout: 8)
            XCTAssertTrue((latestRow.label as String).contains("60 m"))
            XCTAssertTrue((latestRow.label as String).contains("Goal hit"))
            XCTAssertTrue((latestRow.label as String).contains("Target 19–21s"))
            takeScreenshot("Sprint range goal hit in Journal")

            forceTap(latestRow)
            waitFor(app.navigationBars["Set Details"], timeout: 6)

            let sprintResult = app.descendants(matching: .any)
                .matching(identifier: "SetDetail.SprintGoalResult").firstMatch
            waitFor(sprintResult)
            XCTAssertTrue((sprintResult.label as String).contains("Goal hit"))
            XCTAssertTrue((sprintResult.label as String).contains("inside your target range"))
            takeScreenshot("Sprint range goal hit details")

            let detailDistance = textInput("SetDetail.Distance")
            waitFor(detailDistance)
            XCTAssertEqual(detailDistance.value as? String, "60")
            XCTAssertTrue(app.otherElements["SetDetail.Duration"].waitForExistence(timeout: 2))

            let detailSeconds = app.buttons["DurationPicker.Seconds"]
            forceTap(detailSeconds)
            forceTap(app.buttons["25s"])
            let missedResult = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "SetDetail.SprintGoalResult", "Goal missed")
            ).firstMatch
            waitFor(missedResult)
            XCTAssertTrue((missedResult.label as String).contains("4 seconds slower"))
            takeScreenshot("Sprint range goal missed details")
        }
    }

    func testPersonalRecordBadgeAppearsInJournalHistory() {
        step("Launch populated journal") {
            launchApp(fixtureMode: "populated")
            navigateToTab(.journal)
        }

        step("A personal-record set is badged in the history") {
            let list = waitForIdentifier("Journal.List", timeout: 8)
            let prPredicate = NSPredicate(format: "label CONTAINS[c] %@", "personal record")
            let prRow = list.descendants(matching: .any).matching(prPredicate).firstMatch
            if !prRow.waitForExistence(timeout: 4) {
                let globalRow = app.descendants(matching: .any).matching(prPredicate).firstMatch
                XCTAssertTrue(globalRow.waitForExistence(timeout: 4), "Expected at least one PR-badged set in the populated journal")
            }
        }
    }

    func testPersonalBestCardAndLivePRWhileLogging() {
        step("Launch populated journal") {
            launchApp(fixtureMode: "populated")
            navigateToTab(.journal)
        }

        step("Opening an exercise with history shows the personal-best target card") {
            openAddSet()
            selectExercise(identifier: "BenchPress")

            let card = app.descendants(matching: .any).matching(identifier: "AddSet.PersonalBest").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 6), "Personal best card should appear for an exercise with history")
            let heaviest = app.descendants(matching: .any).matching(identifier: "AddSet.PersonalBest.Heaviest").firstMatch
            XCTAssertTrue(heaviest.waitForExistence(timeout: 4), "Heaviest best should be shown")
        }

        step("Entering a heavier weight lights up the live PR banner") {
            let list = addSetListContainer()
            let weightField = textInput("AddSet.Weight")
            waitFor(weightField, timeout: 6)
            if !weightField.isHittable {
                scrollToElement(weightField, in: list, maxSwipes: 6)
            }
            clearAndType(weightField, text: "225")
            dismissKeyboardIfPresent()

            let liveBanner = app.descendants(matching: .any).matching(identifier: "AddSet.LivePR").firstMatch
            XCTAssertTrue(liveBanner.waitForExistence(timeout: 4), "Live PR banner should appear when the entry beats the record")
        }
    }

    private func selectExerciseTemplate(_ identifier: String, file: StaticString = #file, line: UInt = #line) {
        let template = app.buttons[identifier]
        if !template.waitForExistence(timeout: 2) {
            dismissKeyboardIfPresent()
            let editorList = app.descendants(matching: .any).matching(identifier: "ExerciseEditor.List").firstMatch
            let container = editorList.exists ? editorList : (app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch)
            scrollToElement(template, in: container, maxSwipes: 10)
        }
        forceTap(template, timeout: 6, file: file, line: line)
    }

    private func expandExerciseEditorAdvanced(file: StaticString = #file, line: UInt = #line) {
        let advanced = app.buttons["ExerciseEditor.Advanced"]
        if !advanced.waitForExistence(timeout: 2) {
            dismissKeyboardIfPresent()
            let editorList = app.descendants(matching: .any).matching(identifier: "ExerciseEditor.List").firstMatch
            let container = editorList.exists ? editorList : app.collectionViews.firstMatch
            scrollToElement(advanced, in: container, maxSwipes: 12)
        }
        forceTap(advanced, timeout: 6, file: file, line: line)

        let iconMode = app.segmentedControls["ExerciseEditor.IconMode"]
        if !iconMode.waitForExistence(timeout: 2) {
            let editorList = app.descendants(matching: .any).matching(identifier: "ExerciseEditor.List").firstMatch
            let container = editorList.exists ? editorList : app.collectionViews.firstMatch
            scrollToElement(iconMode, in: container, maxSwipes: 8)
        }
    }
}
