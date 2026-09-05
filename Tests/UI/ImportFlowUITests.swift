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

    func testAppleNotesBoundsAndSprintsSaveAllEightSets() {
        launchApp(fixtureMode: "empty", nowISO8601: "2026-09-05T12:00:00Z")
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("9/4/26\n\nStraight Leg Speed Bounds (2 sets)\n\nKnee Drive Speed Bounds (2 sets)\n\nResistance Rope Sprint 2 sets , 50m each\n\nSprints , 2 sets , 50m each")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
        let summary = waitForIdentifier("TextEntry.ReviewSummary", timeout: 15)
        XCTAssertEqual(summary.label, "4 exercises · 8 sets")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "TextEntry.Unparsed.Line.0").firstMatch.exists)
        takeScreenshot("Composer_OwnerNotes_Review")
        let save = waitForIdentifier("TextEntry.Import", timeout: 8)
        XCTAssertTrue(save.isEnabled)
        XCTAssertEqual(save.label, "Add 8 sets to Log")
        forceTap(save)
        XCTAssertEqual(waitForIdentifier("TextEntry.Imported", timeout: 8).label, "Added 8 sets")
        forceTap(waitForIdentifier("TextEntry.Imported.ViewLog", timeout: 8))
        forceTap(waitForIdentifier("Journal.WorkoutHistory", timeout: 8))
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'History.Session.'")).firstMatch
        waitFor(session, timeout: 8)
        forceTap(session)
        _ = waitForIdentifier("History.Repeat", timeout: 8)
        var saved: [String: String] = [:]
        var orderedLabels: [String] = []
        for _ in 0..<8 {
            let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'History.SetLabel.'"))
            for row in rows.allElementsBoundByIndex {
                if saved[row.identifier] == nil { orderedLabels.append(row.label) }
                saved[row.identifier] = row.label
            }
            if saved.count == 8 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertEqual(saved.count, 8)
        let expectedOrder = ["Straight Leg Speed Bounds", "Knee Drive Speed Bounds", "Resistance Rope Sprint", "Sprint"]
            .flatMap { [$0, $0] }
        XCTAssertEqual(orderedLabels.count, expectedOrder.count)
        for (label, name) in zip(orderedLabels, expectedOrder) {
            XCTAssertTrue(label.contains(". " + name + ","), "Saved History must preserve source order: expected \(name), received \(label)")
        }
        // The seeded library's exact alias maps "Sprints" to "Sprint".
        // Row accessibility includes an import-provenance prefix.
        for name in ["Straight Leg Speed Bounds", "Knee Drive Speed Bounds", "Resistance Rope Sprint", "Sprint"] {
            let labels = saved.values.filter { $0.contains(". " + name + ",") }
            XCTAssertEqual(labels.count, 2, "Each source exercise must save two distinct sets")
            if name.contains("Bounds") {
                XCTAssertTrue(labels.allSatisfy { !$0.contains(" reps") }, "Unspecified reps must remain unspecified")
            } else {
                XCTAssertTrue(labels.allSatisfy { $0.contains("50 m") }, "Each sprint must retain its 50 meter distance")
            }
        }
        takeScreenshot("Composer_OwnerNotes_SavedHistory")
    }

    func testRemovingEarlierUnorganizedLinePreservesAnotherPendingEdit() {
        launchApp(fixtureMode: "empty")
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Bench Press 3x8 @ 185 lb\nround 2 of 3 felt easy\nround 2 of 3 felt easy")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
        _ = waitForIdentifier("TextEntry.ReviewSummary", timeout: 15)
        let second = app.descendants(matching: .any).matching(identifier: "TextEntry.Unparsed.Line.1").firstMatch
        scrollToElement(second, in: app.collectionViews.firstMatch)
        waitFor(second, timeout: 8)
        clearAndType(second, text: "Second detail edited")
        dismissKeyboardIfPresent()
        let firstKeep = app.buttons["TextEntry.Unparsed.KeepNote.0"]
        scrollToElement(firstKeep, in: app.collectionViews.firstMatch)
        forceTap(firstKeep)
        let surviving = app.descendants(matching: .any).matching(identifier: "TextEntry.Unparsed.Line.0").firstMatch
        scrollToElement(surviving, in: app.collectionViews.firstMatch)
        waitFor(surviving, timeout: 8)
        XCTAssertEqual((surviving.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "Second detail edited")
    }

    func testUnorganizedLineMustBeKeptBeforeSaving() {
        launchApp(fixtureMode: "empty")
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        editor.tap()
        editor.typeText("Bench Press 3x8 @ 185 lb\nround 2 of 3 felt easy")
        dismissKeyboardIfPresent()
        forceTap(waitForIdentifier("TextEntry.Preview", timeout: 8))
        let save = waitForIdentifier("TextEntry.Import", timeout: 10)
        XCTAssertFalse(save.isEnabled)
        let keep = app.buttons["TextEntry.Unparsed.KeepNote.0"]
        scrollToElement(keep, in: app.collectionViews.firstMatch)
        forceTap(keep)
        XCTAssertTrue(save.isEnabled)
        forceTap(save)
        XCTAssertTrue(waitForIdentifier("TextEntry.Imported", timeout: 8).exists)
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
