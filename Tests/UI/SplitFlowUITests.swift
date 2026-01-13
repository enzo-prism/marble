import XCTest

final class SplitFlowUITests: MarbleUITestCase {
    func testEditSplitDay() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.split)

        let mondayRow = waitForIdentifier("Split.Day.Monday")
        forceTap(mondayRow)

        let addPlannedSet = app.buttons["SplitDayEditor.AddPlannedSet"]
        if !addPlannedSet.isHittable {
            app.swipeUp()
        }
        forceTap(addPlannedSet)

        let benchRow = app.buttons.matching(identifier: "ExercisePicker.Row.BenchPress").firstMatch
        waitFor(benchRow)
        forceTap(benchRow)

        let plannedBench = waitForIdentifier("SplitDayEditor.PlannedSet.BenchPress")
        forceTap(plannedBench)

        waitFor(app.navigationBars["Log Set"])
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
