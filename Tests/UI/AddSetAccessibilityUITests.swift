import XCTest

final class AddSetAccessibilityUITests: MarbleUITestCase {
    func testExercisePickerAndSaveActionsRemainUsableAtLargestAccessibilityText() {
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

        let saveAndNext = app.buttons["AddSet.SaveAndNext"]
        let bottomSave = app.buttons["AddSet.BottomSave"]

        let list = addSetListContainer()
        scrollToElement(saveAndNext, in: list, maxSwipes: 20)
        waitFor(saveAndNext, timeout: 8)
        XCTAssertTrue(saveAndNext.isHittable)

        scrollToElement(bottomSave, in: list, maxSwipes: 8)
        waitFor(bottomSave, timeout: 8)
        XCTAssertTrue(bottomSave.isHittable)
        XCTAssertLessThanOrEqual(saveAndNext.frame.maxY, bottomSave.frame.minY)
        takeScreenshot("AddSet_A11y_InlineSaveActions")
    }
}
