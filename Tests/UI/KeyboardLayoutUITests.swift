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
        XCTAssertTrue(app.navigationBars.buttons["AddSet.Save"].exists)

        takeScreenshot("AddSet_KeyboardVisible")

        dismissKeyboardIfPresent()

        let list = addSetListContainer()
        let notesField = textInput("AddSet.Notes")
        scrollToElement(notesField, in: list)
        waitFor(notesField)
        notesField.tap()
        XCTAssertTrue(app.keyboards.element.exists)
        takeScreenshot("AddSet_NotesKeyboardVisible")
    }
}
