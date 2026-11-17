import XCTest

/// "Ask your journal" end to end on the deterministic path (UI-test hosts
/// never call the on-device model): History's toolbar opens the sheet, an
/// example question answers from the seeded journal, and the answer's card
/// opens the workout or exercise it came from.
final class AskJournalUITests: MarbleUITestCase {
    private func openAsk() {
        navigateToTab(.journal)
        forceTap(waitForIdentifier("Journal.WorkoutHistory", timeout: 8))
        let ask = waitForIdentifier("Ask.Button", timeout: 8)
        XCTAssertGreaterThanOrEqual(ask.frame.height, 44)
        forceTap(ask)
        waitForIdentifier("Ask.Field", timeout: 8)
    }

    func testExampleQuestionAnswersWithATappableCard() {
        launchApp(fixtureMode: "screenshots")
        openAsk()
        let example = waitForIdentifier("Ask.Example.0", timeout: 8)
        XCTAssertGreaterThanOrEqual(example.frame.height, 44)
        forceTap(example)
        let answer = waitForIdentifier("Ask.Answer", timeout: 15)
        XCTAssertFalse(answer.label.isEmpty)
        let footer = waitForIdentifier("Ask.Footer", timeout: 5)
        XCTAssertEqual(footer.label, "Answered on this device from your journal.")
        let card = waitForIdentifier("Ask.Card.0", timeout: 5)
        takeScreenshot("Ask_Answer")
        forceTap(card)
        // A session card pushes the workout; an exercise card covers the
        // sheet with that exercise's progress. Either way the card leaves view.
        let left = expectation(for: NSPredicate(format: "exists == false OR hittable == false"), evaluatedWith: card)
        wait(for: [left], timeout: 8)
    }

    func testTypedQuestionOutsideScopeExplainsWhatMarbleCanAnswer() {
        launchApp(fixtureMode: "empty")
        openAsk()
        let field = waitForIdentifier("Ask.Field", timeout: 5)
        forceTap(field)
        field.typeText("Tell me a joke\n")
        waitForIdentifier("Ask.Unanswerable", timeout: 15)
        XCTAssertTrue(waitForIdentifier("Ask.Example.0", timeout: 5).exists)
        forceTap(waitForIdentifier("Ask.Done"))
        XCTAssertTrue(waitForIdentifier("Ask.Button", timeout: 8).exists)
    }
}
