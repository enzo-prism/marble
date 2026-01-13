import XCTest

final class SplitFlowUITests: MarbleUITestCase {
    func testEditSplitDay() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.split)

        let mondayRow = waitForIdentifier("Split.Day.Monday")
        forceTap(mondayRow)

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
