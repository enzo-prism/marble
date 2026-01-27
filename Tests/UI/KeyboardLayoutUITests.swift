import XCTest

final class KeyboardLayoutUITests: MarbleUITestCase {
    func testAddSetKeyboardLayout() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.journal)

        openAddSet()
        selectExercise(identifier: "BenchPress")

        let weightField = textInput("AddSet.Weight")
        waitFor(weightField)
        weightField.tap()
        XCTAssertTrue(app.keyboards.element.exists)

        takeScreenshot("AddSet_KeyboardVisible")

        let addNoteButton = app.buttons["AddSet.AddNote"]
        if !addNoteButton.exists {
            let list = addSetListContainer()
            for _ in 0..<3 {
                if list.exists {
                    list.swipeDown()
                } else {
                    app.swipeDown()
                }
            }
        }
        if addNoteButton.exists {
            addNoteButton.tap()
        }
        let notesField = textInput("AddSet.Notes")
        waitFor(notesField)
        notesField.tap()
        XCTAssertTrue(app.keyboards.element.exists)
        takeScreenshot("AddSet_NotesKeyboardVisible")
    }
}
