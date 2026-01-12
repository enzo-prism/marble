import XCTest

final class SupplementsFlowUITests: MarbleUITestCase {
    func testSupplementQuickAddAndEdit() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.supplements)

        let creatineButton = app.buttons["Supplements.QuickAdd.Creatine"]
        waitFor(creatineButton)
        creatineButton.tap()
        _ = app.otherElements["Toast"].waitForExistence(timeout: 3)

        let proteinButton = app.buttons["Supplements.QuickAdd.ProteinPowder"]
        waitFor(proteinButton)
        proteinButton.tap()
        _ = app.otherElements["Toast"].waitForExistence(timeout: 3)

        let list = waitForIdentifier("Supplements.List", timeout: 5)
        let entryButton = supplementRow(named: "Creatine", in: list)
        waitFor(entryButton, timeout: 5)
        entryButton.tap()

        let doseField = textInput("SupplementDetail.Dose")
        waitFor(doseField)
        clearAndType(doseField, text: "7")

        let notesField = textInput("SupplementDetail.Notes")
        waitFor(notesField)
        clearAndType(notesField, text: "Post workout")

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        waitFor(backButton)
        backButton.tap()
        let updatedList = waitForIdentifier("Supplements.List", timeout: 5)
        let updatedRow = supplementRow(named: "Creatine", in: updatedList)
        waitFor(updatedRow, timeout: 5)
    }
}
