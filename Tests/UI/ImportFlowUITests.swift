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

    /// Text entry is the default Add destination rather than a nested import sheet.
    func testTypedWorkoutIsTheDefaultPersistentDestination() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.addWorkout)
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 5)
        XCTAssertTrue(app.buttons["TextEntry.ChooseFile"].exists)

        editor.tap()
        editor.typeText("Bench 3x8 @ 185 lb")
        dismissKeyboardIfPresent()
        navigateToTab(.journal)
        navigateToTab(.addWorkout)
        XCTAssertTrue((editor.value as? String)?.contains("Bench 3x8") == true)
    }

    func testAddTabReviewsBeforeSavingStructuredSets() {
        launchApp(fixtureMode: "empty")

        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Bench Press 3x8 @ 185 lb rest 90s")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))

        waitFor(app.navigationBars["Review Workout"], timeout: 10)
        XCTAssertTrue(waitForIdentifier("TextEntry.Title", timeout: 8).exists)

        // Review is non-destructive: nothing reaches the Log before confirmation.
        navigateToTab(.journal)
        XCTAssertTrue(waitForIdentifier("Journal.StartChecklist", timeout: 8).exists)
        navigateToTab(.addWorkout)

        forceTap(waitForIdentifier("TextEntry.Import", timeout: 8))
        XCTAssertTrue(waitForIdentifier("TextEntry.Imported", timeout: 8).exists)
        forceTap(waitForIdentifier("TextEntry.Imported.ViewLog", timeout: 8))

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'SetRow.'"))
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Bench Press'")).firstMatch.exists)
    }

    func testDuplicateTypedWorkoutCanBeSavedAfterChangingReviewDate() throws {
        launchApp(fixtureMode: "empty")
        let workout = "Bench Press 1x8 @ 185 lb rest 90s"

        func reviewWorkout() {
            let editor = app.textViews["TextEntry.Editor"]
            waitFor(editor, timeout: 8)
            clearAndType(editor, text: workout)
            dismissKeyboardIfPresent()
            forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
            waitFor(app.navigationBars["Review Workout"], timeout: 10)
        }

        reviewWorkout()
        forceTap(waitForIdentifier("TextEntry.Import", timeout: 8))
        _ = waitForIdentifier("TextEntry.Imported", timeout: 8)
        forceTap(waitForIdentifier("TextEntry.Imported.AddAnother", timeout: 8))
        reviewWorkout()

        let duplicate = waitForIdentifier("TextEntry.AlreadyImported", timeout: 8)
        forceTap(waitForIdentifier("TextEntry.Import", timeout: 8))
        // An accidental second tap must retain the editable review, not report
        // a successful import or discard the draft.
        XCTAssertTrue(app.navigationBars["Review Workout"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "TextEntry.Imported").firstMatch.exists)
        XCTAssertTrue(duplicate.exists)

        let date = waitForIdentifier("TextEntry.Date", timeout: 8)
        scrollToElement(date, in: app.collectionViews.firstMatch)
        let dateButton = date.buttons.firstMatch
        waitFor(dateButton)
        let originalDate = try XCTUnwrap(dateButton.value as? String)
        forceTap(dateButton)
        // The fixture is January 15. Native calendar accessibility includes
        // the day number, whether exposed alone or within a full date label.
        let previousDay = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*\\b14\\b.*")).firstMatch
        waitFor(previousDay, timeout: 5)
        forceTap(previousDay)
        // Compact pickers can remain open after selecting a day.
        forceTap(app.navigationBars["Review Workout"])
        XCTAssertNotEqual(dateButton.value as? String, originalDate)
        let duplicateCleared = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: duplicate
        )
        wait(for: [duplicateCleared], timeout: 5)
        forceTap(waitForIdentifier("TextEntry.Import", timeout: 8))
        _ = waitForIdentifier("TextEntry.Imported", timeout: 8)
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
        // The fixture's imported row starts beneath the top navigation chrome.
        // Bring an unobscured tappable portion into the journal's visible frame.
        scrollToElement(importedRow, in: journalList)
        XCTAssertTrue(importedRow.exists)
        forceTap(importedRow)

        let detailTitle = app.navigationBars["Set Details"]
        waitFor(detailTitle, timeout: 5)
        let detailList = app.collectionViews.firstMatch
        waitFor(detailList, timeout: 5)
        let importedSection = app.descendants(matching: .any).matching(identifier: "SetDetail.Imported").firstMatch
        if !importedSection.waitForExistence(timeout: 4) {
            // Set Detail gained more editable fields over time; a single blind
            // swipe no longer guarantees this lower section is materialized.
            scrollToElement(importedSection, in: detailList)
        }
        XCTAssertTrue(importedSection.waitForExistence(timeout: 4), "Set detail must show the imported workout section")
    }
}
