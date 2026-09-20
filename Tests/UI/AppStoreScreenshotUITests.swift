import XCTest

/// Deterministic, one-screen-per-test captures for the App Store pipeline.
/// These are intentionally UI tests so every image is produced from the real
/// shipping interface and can be regenerated on both iPhone and iPad.
final class AppStoreScreenshotUITests: MarbleUITestCase {
    private func launchScreenshotApp(
        initialTab: String? = nil,
        nowISO8601: String = "2026-07-16T04:30:00.000Z",
        extraEnvironment: [String: String] = [:]
    ) {
        var environment = ["MARBLE_APP_STORE_SCREENSHOTS": "1"]
        if let initialTab {
            environment["MARBLE_INITIAL_TAB"] = initialTab
        }
        environment.merge(extraEnvironment) { _, new in new }
        launchApp(
            fixtureMode: "screenshots",
            // 9:30 PM PDT: the deterministic fixture includes a real same-day
            // workout, so Trends shows the shipping Daily Highlights surface.
            nowISO8601: nowISO8601,
            forceReduceTransparency: true,
            extraEnvironment: environment
        )
    }

    func test12HistoryAndRepeat() {
        launchScreenshotApp(initialTab: "add", nowISO8601: "2026-07-15T16:30:00.000Z")
        forceTap(waitForIdentifier("Workout.Open", timeout: 8))
        forceTap(waitForIdentifier("Workout.Finish", timeout: 8))
        forceTap(waitForIdentifier("Workout.Finish.Confirm", timeout: 8))
        app.navigationBars["Workout"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        navigateToTab(.journal)
        forceTap(waitForIdentifier("Journal.WorkoutHistory", timeout: 8))
        let session = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'History.Session.'")).firstMatch
        waitFor(session, timeout: 10)
        takeScreenshot("12-workout-history")
        forceTap(session)
        let repeatButton = waitForIdentifier("History.Repeat", timeout: 8)
        XCTAssertTrue(repeatButton.isEnabled)
        forceTap(repeatButton)
        _ = waitForIdentifier("TextEntry.Title", timeout: 8)
        _ = waitForIdentifier("TextEntry.Import", timeout: 8)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "TextEntry.Imported").firstMatch.exists)
        takeScreenshot("13-repeat-workout")
    }

    func test00AddComposer() {
        launchScreenshotApp(initialTab: "add")
        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 10)
        clearAndType(editor, text: "Bench Press 3x8 @ 185 lb\nShoulder Press 3x10 @ 95 lb\nSquat 3x5 @ 225 lb")
        forceTap(waitForIdentifier("TextEntry.Keyboard.Done", timeout: 5))
        takeScreenshot("00-add-composer")
    }

    func test11DailyHighlights() {
        launchScreenshotApp(initialTab: "trends")
        revealDetailedTrends()
        _ = waitForIdentifier("Trends.DailyHighlights", timeout: 10)
        let quote = app.buttons["Trends.DailyHighlights.Quote"]
        waitFor(quote, timeout: 8)
        quote.swipeRight()
        takeScreenshot("11-daily-highlights")
    }

    func test01Journal() {
        launchScreenshotApp()
        navigateToTab(.journal)
        _ = waitForIdentifier("Journal.List", timeout: 12)
        takeScreenshot("01-journal")
    }

    func test02PasteOrTypeReview() {
        launchScreenshotApp()
        navigateToTab(.addWorkout)

        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        clearAndType(editor, text: """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2026-07-14 18:00:00,Bench Press,0,185,8
        Push Day,2026-07-14 18:00:00,Shoulder Press,0,95,10
        Pull Day,2026-07-15 18:00:00,Deadlift,0,225,5
        Pull Day,2026-07-15 18:00:00,Pull Ups,0,0,8
        """)
        let keyboardDone = waitForIdentifier("TextEntry.Keyboard.Done", timeout: 5)
        forceTap(keyboardDone)
        let preview = waitForIdentifier("TextEntry.Preview", timeout: 8)
        if !preview.isHittable {
            scrollToElement(preview, in: app.scrollViews.firstMatch)
        }
        forceTap(preview)

        waitFor(app.navigationBars["Review Workouts"], timeout: 12)
        waitForIdentifier("TextEntry.Batch.Import", timeout: 8)
        XCTAssertTrue(app.staticTexts["Push Day"].exists)
        XCTAssertTrue(app.staticTexts["Pull Day"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tue, Jul 14")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Wed, Jul 15")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hevy")).firstMatch.exists)
        takeScreenshot("02-paste-or-type-review")
    }

    func test03FastSetLogger() {
        launchScreenshotApp()
        navigateToTab(.journal)
        openAddSet()
        selectExercise(identifier: "BenchPress")
        _ = waitForIdentifier("AddSet.List", timeout: 10)
        takeScreenshot("03-fast-set-logger")
    }

    func test04ActiveWorkout() {
        launchScreenshotApp(
            initialTab: "add",
            extraEnvironment: ["MARBLE_ENABLE_REST_PILL": "1"]
        )
        tapBottomAccessory(waitForIdentifier("SessionPill", timeout: 10))
        _ = waitForIdentifier("Workout.List", timeout: 10)
        _ = waitForIdentifier("Workout.Finish", timeout: 10)
        let workoutSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Set.'"))
            .firstMatch
        waitFor(workoutSet, timeout: 10)
        takeScreenshot("04-active-workout")
    }

    func test05StrengthTrends() {
        launchScreenshotApp(initialTab: "trends")
        _ = waitForIdentifier("Trends.TopExercises", timeout: 15)
        _ = waitForIdentifier("Trends.Details.Toggle", timeout: 15)
        let quote = app.buttons["Trends.Overview.Quote"]
        waitFor(quote, timeout: 8)
        quote.swipeRight()
        takeScreenshot("05-strength-trends")
    }

    func test06SprintPrescription() {
        launchScreenshotApp()
        navigateToTab(.journal)
        openAddSet()
        selectExercise(identifier: "Sprint")
        _ = waitForIdentifier("AddSet.Sprint.Distance", timeout: 10)
        takeScreenshot("06-sprint-prescription")
    }

    func test08EmojiExerciseLibrary() {
        launchScreenshotApp(initialTab: "add")
        openAddToolbarAction("Workout.Settings")
        // 2.2 moved Data & Backups behind the new Settings screen, below the
        // fold of a lazy List — it isn't in the tree until we scroll to it.
        scrollToElement(app.descendants(matching: .any).matching(identifier: "Settings.Data").firstMatch, in: app)
        forceTap(waitForIdentifier("Settings.Data", timeout: 10))
        forceTap(waitForIdentifier("Data.ExerciseLibrary", timeout: 10))
        _ = waitForIdentifier("ManageExercises.List", timeout: 10)
        takeScreenshot("08-emoji-exercise-library")
    }

    func test07TrainingCalendar() {
        launchScreenshotApp()
        navigateToTab(.calendar)
        _ = waitForIdentifier("Calendar.Header", timeout: 10)
        XCTAssertFalse(app.buttons["Calendar.TestOpenEmpty"].exists)
        XCTAssertFalse(app.buttons["Calendar.TestOpenPopulated"].exists)
        takeScreenshot("07-training-calendar")
    }

    func test09PrivateBackup() {
        launchScreenshotApp(initialTab: "add")
        openAddToolbarAction("Workout.Settings")
        let data = app.buttons["Settings.Data"]
        let list = app.collectionViews.firstMatch
        if list.exists { scrollToElement(data, in: list) }
        else { scrollToElement(data, in: app) }
        waitFor(data, timeout: 10)
        data.tap()
        _ = waitForIdentifier("Data.Summary", timeout: 12)
        _ = waitForIdentifier("Data.Export", timeout: 10)
        _ = waitForIdentifier("Data.Restore", timeout: 10)
        takeScreenshot("09-private-backup")
    }

    func test10PrivateOnboarding() {
        launchScreenshotApp(extraEnvironment: ["MARBLE_FORCE_ONBOARDING": "1"])
        _ = waitForIdentifier("Onboarding.Continue", timeout: 10)
        let privacyCopy = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "stays on this device"))
            .firstMatch
        XCTAssertTrue(privacyCopy.waitForExistence(timeout: 5))
        takeScreenshot("10-private-onboarding")
    }
}
