import XCTest

final class SplitFlowUITests: MarbleUITestCase {
    func testEditSplitDay() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.addWorkout)

        openAddToolbarAction("Workout.Plan")

        let mondayRow = waitForIdentifier("Split.Day.Monday")
        forceTap(mondayRow)

        let editorList = waitForIdentifier("SplitDayEditor.List", timeout: 8)
        let addPlannedSet = app.buttons["SplitDayEditor.AddPlannedSet"]
        if !addPlannedSet.waitForExistence(timeout: 2) || !addPlannedSet.isHittable {
            scrollToElement(addPlannedSet, in: editorList, maxSwipes: 8)
        }
        XCTAssertTrue(addPlannedSet.isHittable)
        addPlannedSet.tap()

        let exerciseList = waitForIdentifier("ExercisePicker.List", timeout: 8)
        let benchRow = app.buttons.matching(identifier: "ExercisePicker.Row.BenchPress").firstMatch
        if !benchRow.waitForExistence(timeout: 2) {
            let searchField = app.searchFields.firstMatch
            waitFor(searchField)
            searchField.tap()
            searchField.typeText("Bench Press")
        }
        waitFor(benchRow, timeout: 8)
        if !benchRow.isHittable {
            scrollToElement(benchRow, in: exerciseList, maxSwipes: 8)
        }
        forceTap(benchRow)

        let plannedBench = waitForIdentifier("SplitDayEditor.PlannedSet.BenchPress")
        plannedBench.tap()

        waitFor(app.navigationBars["Log Set"], timeout: 15)
        let sessionContext = waitForIdentifier("AddSet.SessionContext", timeout: 6)
        XCTAssertTrue(sessionContext.exists)
        let exercisePicker = app.buttons["AddSet.ExercisePicker"]
        waitFor(exercisePicker)
        XCTAssertEqual(exercisePicker.value as? String, "Bench Press")
        dismissSheet()
        waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)

        let titleField = textInput("SplitDayEditor.Title")
        clearAndType(titleField, text: "Push")

        let addNote = app.buttons["SplitDayEditor.AddNote"]
        if addNote.exists {
            addNote.tap()
        }
        let notesField = textInput("SplitDayEditor.Notes")
        clearAndType(notesField, text: "Chest + triceps")

        let save = app.buttons["SplitDayEditor.Save"]
        forceTap(save)
        waitForIdentifier("Split.List")

        forceTap(mondayRow)
        let updatedTitle = textInput("SplitDayEditor.Title")
        XCTAssertEqual(updatedTitle.value as? String, "Push")
    }
}
