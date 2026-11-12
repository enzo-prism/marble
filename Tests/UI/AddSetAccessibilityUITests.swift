import XCTest

final class AddSetAccessibilityUITests: MarbleUITestCase {
    func testExercisePickerAndSaveActionsRemainUsableAtLargestAccessibilityText() throws {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated",
            extraEnvironment: ["MARBLE_INITIAL_TAB": "journal"]
        )
        openAddSet()
        selectExercise(identifier: "BenchPress")

        let picker = app.buttons["AddSet.ExercisePicker"]
        waitFor(picker, timeout: 8)
        XCTAssertTrue(picker.isHittable)
        XCTAssertEqual(picker.label, "Exercise, Bench Press")
        XCTAssertEqual(picker.value as? String, "Bench Press")
        takeScreenshot("AddSet_A11y_ExerciseRow")

        let heading = app.staticTexts["AddSet.LastTimeHeading"]
        scrollToElement(heading, in: addSetListContainer())
        XCTAssertTrue(try isAddSetHistoryHeadingFullyDrawn(),
                      "The full Last time heading must be drawn inside its bounds at XXXL.")
        takeScreenshot("AddSet_A11y_HistoryHeading")

        let saveAndNext = app.buttons["AddSet.SaveAndNext"]
        let toolbarSave = app.navigationBars.buttons["AddSet.Save"]

        let list = addSetListContainer()
        scrollToElement(saveAndNext, in: list, maxSwipes: 20)
        waitFor(saveAndNext, timeout: 8)
        XCTAssertTrue(saveAndNext.isHittable)

        waitFor(toolbarSave, timeout: 8)
        XCTAssertTrue(toolbarSave.isHittable)
        takeScreenshot("AddSet_A11y_SaveActions")

        let cancel = app.navigationBars.buttons["AddSet.Cancel"]
        waitFor(cancel, timeout: 8)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertEqual(cancel.label, "Cancel")
        for (identifier, title) in [("AddSet.Cancel", "Cancel"), ("AddSet.Save", "Save")] {
            XCTAssertTrue(try isNativeToolbarTitleFullyDrawn(identifier: identifier, title: title),
                          "The full native \(title) title must be drawn inside its bounds at XXXL.")
        }
        forceTap(cancel)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8))
    }
}
