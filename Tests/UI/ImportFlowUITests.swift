import XCTest

final class ImportFlowUITests: MarbleUITestCase {
    /// The import hub is reachable from the Journal toolbar, always offers Apple Health and
    /// the Garmin-via-Health explainer, and dismisses cleanly back to the Journal.
    func testOpenImportHubFromJournal() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.journal)

        let importButton = app.buttons["Journal.ImportWorkouts"]
        waitFor(importButton)
        importButton.tap()

        // Apple Health is always present (its Connect action), as is the Garmin bridge.
        let appleHealthConnect = app.buttons["Import.appleHealth.Connect"]
        waitFor(appleHealthConnect, timeout: 5)

        let garminBridge = waitForIdentifier("Import.GarminBridge", timeout: 5)
        XCTAssertTrue(garminBridge.exists)
        XCTAssertTrue(app.buttons["Import.GarminBridge.Open"].exists)

        let done = app.buttons["Import.Done"]
        waitFor(done)
        done.tap()

        let journalList = waitForIdentifier("Journal.List", timeout: 5)
        XCTAssertTrue(journalList.exists)
    }

    /// The hub's history section lists previously imported workouts and opens
    /// the read-only detail sheet with the full stats grid.
    func testImportHistoryOpensWorkoutDetail() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.journal)

        let importButton = app.buttons["Journal.ImportWorkouts"]
        waitFor(importButton)
        importButton.tap()

        let importList = app.collectionViews.firstMatch
        let history = app.descendants(matching: .any).matching(identifier: "Import.History").firstMatch
        if !history.waitForExistence(timeout: 3) {
            scrollToElement(history, in: importList.exists ? importList : app.otherElements.firstMatch)
        }

        // The fixture seeds one Garmin run; its history row opens the detail sheet.
        let historyRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Running"))
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Garmin"))
            .firstMatch
        waitFor(historyRow, timeout: 5)
        forceTap(historyRow)

        waitForIdentifier("ImportDetail.View", timeout: 5)
        let stats = waitForIdentifier("ImportDetail.Stats", timeout: 5)
        XCTAssertTrue(stats.exists)
        let source = app.descendants(matching: .any).matching(identifier: "ImportDetail.Source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 3))

        dismissSheet()
    }

    /// Imported sets carry a provenance badge in the journal and a read-only
    /// "Imported Workout" section in the set detail screen.
    func testJournalShowsImportedProvenance() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.journal)

        let journalList = waitForIdentifier("Journal.List", timeout: 5)
        let badge = journalList.descendants(matching: .any).matching(identifier: "ImportedBadge").firstMatch
        if !badge.waitForExistence(timeout: 3) {
            scrollToElement(badge, in: journalList)
        }
        XCTAssertTrue(badge.exists, "The imported run must show its origin badge in the journal")

        // Open the imported set's detail and check the provenance section.
        let importedRow = journalList.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "SetRow."))
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Imported from Garmin"))
            .firstMatch
        waitFor(importedRow, timeout: 5)
        forceTap(importedRow)

        let importedSection = app.descendants(matching: .any).matching(identifier: "SetDetail.Imported").firstMatch
        if !importedSection.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        XCTAssertTrue(importedSection.waitForExistence(timeout: 4), "Set detail must show the imported workout section")
    }
}
