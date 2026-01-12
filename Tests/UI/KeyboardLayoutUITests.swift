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

        let saveButton = app.buttons["AddSet.Save"]
        if !saveButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(saveButton.exists)
        takeScreenshot("AddSet_KeyboardVisible")

        if app.buttons["AddSet.AddNote"].exists {
            app.buttons["AddSet.AddNote"].tap()
        }
        let notesField = textInput("AddSet.Notes")
        waitFor(notesField)
        notesField.tap()
        XCTAssertTrue(app.keyboards.element.exists)
        takeScreenshot("AddSet_NotesKeyboardVisible")
    }
}
