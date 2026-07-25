import XCTest

/// Deterministic, one-screen-per-test captures for the App Store pipeline.
/// These are intentionally UI tests so every image is produced from the real
/// shipping interface and can be regenerated on both iPhone and iPad.
final class AppStoreScreenshotUITests: MarbleUITestCase {
    private func launchScreenshotApp(
        initialTab: String? = nil,
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
            nowISO8601: "2026-07-16T04:30:00.000Z",
            forceReduceTransparency: true,
            extraEnvironment: environment
        )
    }

    func test01Journal() {
        launchScreenshotApp()
        navigateToTab(.journal)
        _ = waitForIdentifier("Journal.List", timeout: 12)
        takeScreenshot("01-journal")
    }

    func test02FastSetLogger() {
        launchScreenshotApp()
        navigateToTab(.journal)
        openAddSet()
        selectExercise(identifier: "BenchPress")
        _ = waitForIdentifier("AddSet.List", timeout: 10)
        takeScreenshot("02-fast-set-logger")
    }

    func test03StrengthTrends() {
        launchScreenshotApp(initialTab: "trends")
        _ = waitForIdentifier("Trends.Focus", timeout: 15)
        let dailyHighlights = app.descendants(matching: .any)
            .matching(identifier: "Trends.DailyHighlights")
            .firstMatch
        scrollToElement(dailyHighlights, in: app)
        _ = waitForIdentifier("Trends.DailyHighlights", timeout: 15)
        takeScreenshot("03-strength-trends")
    }

    func test04ActiveWorkout() {
        launchScreenshotApp(initialTab: "split")
        _ = waitForIdentifier("Workout.Finish", timeout: 10)
        let workoutSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Set.'"))
            .firstMatch
        waitFor(workoutSet, timeout: 10)
        takeScreenshot("04-active-workout")
    }

    func test05SprintPrescription() {
        launchScreenshotApp()
        navigateToTab(.journal)
        openAddSet()
        selectExercise(identifier: "Sprint")
        _ = waitForIdentifier("AddSet.Sprint.Distance", timeout: 10)
        takeScreenshot("05-sprint-prescription")
    }

    func test06EmojiExerciseLibrary() {
        launchScreenshotApp(initialTab: "split")
        forceTap(waitForIdentifier("Workout.Data", timeout: 10))
        // 2.2 moved Data & Backups behind the new Settings screen, below the
        // fold of a lazy List — it isn't in the tree until we scroll to it.
        scrollToElement(app.descendants(matching: .any).matching(identifier: "Settings.Data").firstMatch, in: app)
        forceTap(waitForIdentifier("Settings.Data", timeout: 10))
        forceTap(waitForIdentifier("Data.ExerciseLibrary", timeout: 10))
        _ = waitForIdentifier("ManageExercises.List", timeout: 10)
        takeScreenshot("06-emoji-exercise-library")
    }

    func test07TrainingCalendar() {
        launchScreenshotApp()
        navigateToTab(.calendar)
        _ = waitForIdentifier("Calendar.Header", timeout: 10)
        XCTAssertFalse(app.buttons["Calendar.TestOpenEmpty"].exists)
        XCTAssertFalse(app.buttons["Calendar.TestOpenPopulated"].exists)
        takeScreenshot("07-training-calendar")
    }

    func test08PrivateBackup() {
        launchScreenshotApp(initialTab: "split")
        forceTap(waitForIdentifier("Workout.Data", timeout: 10))
        // 2.2 moved Data & Backups behind the new Settings screen, below the
        // fold of a lazy List — it isn't in the tree until we scroll to it.
        scrollToElement(app.descendants(matching: .any).matching(identifier: "Settings.Data").firstMatch, in: app)
        forceTap(waitForIdentifier("Settings.Data", timeout: 10))
        _ = waitForIdentifier("Data.Summary", timeout: 12)
        _ = waitForIdentifier("Data.Export", timeout: 10)
        _ = waitForIdentifier("Data.Restore", timeout: 10)
        takeScreenshot("08-private-backup")
    }

    func test09PrivateOnboarding() {
        launchScreenshotApp(extraEnvironment: ["MARBLE_FORCE_ONBOARDING": "1"])
        _ = waitForIdentifier("Onboarding.Continue", timeout: 10)
        let privacyCopy = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "stays on this device"))
            .firstMatch
        XCTAssertTrue(privacyCopy.waitForExistence(timeout: 5))
        takeScreenshot("09-private-onboarding")
    }

    func test10Settings() {
        launchScreenshotApp(initialTab: "split")
        forceTap(waitForIdentifier("Workout.Data", timeout: 10))
        _ = waitForIdentifier("Settings.WeightUnit", timeout: 10)
        _ = waitForIdentifier("Settings.WeeklyTarget", timeout: 10)
        _ = waitForIdentifier("Settings.DailyHighlights", timeout: 10)
        takeScreenshot("10-settings")
    }
}
