import XCTest

final class WorkoutFlowUITests: MarbleUITestCase {
    func testStartWorkoutReachableFromDefaultAddTab() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.addWorkout)

        forceTap(waitForIdentifier("Workout.Open"))
        waitForIdentifier("Workout.List", timeout: 8)
        forceTap(waitForIdentifier("Workout.Start"))
        waitForIdentifier("Workout.Finish", timeout: 8)
    }

    func testAddWorkoutSupportsLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated"
        )
        navigateToTab(.addWorkout)

        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        XCTAssertTrue(editor.isHittable)
        XCTAssertGreaterThan(editor.frame.height, 180, "The primary editor must remain useful at accessibility sizes")
        XCTAssertTrue(waitForIdentifier("TextEntry.Preview", timeout: 8).exists)
    }

    func testWorkoutTextCanBeClearedWithoutSelectingEditorText() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.addWorkout)

        let editor = app.textViews["TextEntry.Editor"]
        waitFor(editor, timeout: 8)
        forceTap(editor)
        editor.typeText("Bench press 3x8 @ 185 lb")

        let clear = waitForIdentifier("TextEntry.Clear", timeout: 8)
        XCTAssertTrue(clear.isHittable)
        forceTap(clear)

        XCTAssertEqual(editor.value as? String, "", "Clear should empty the workout draft in one explicit action.")
        XCTAssertFalse(app.buttons["TextEntry.Preview"].isEnabled)
    }

    func testActiveWorkoutAccessoryOpensAndFinishesWorkout() {
        launchApp(
            fixtureMode: "screenshots",
            extraEnvironment: ["MARBLE_ENABLE_REST_PILL": "1"]
        )
        navigateToTab(.addWorkout)

        tapBottomAccessory(waitForIdentifier("SessionPill", timeout: 8))
        waitForIdentifier("Workout.List", timeout: 8)
        let workoutSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Set.'"))
            .firstMatch
        waitFor(workoutSet, timeout: 8)

        forceTap(waitForIdentifier("Workout.AddSet", timeout: 8))
        waitForIdentifier("AddSet.List", timeout: 8)
        forceTap(waitForIdentifier("AddSet.Cancel", timeout: 8))
        waitForIdentifier("Workout.List", timeout: 8)

        forceTap(waitForIdentifier("Workout.Finish"))

        let finish = app.buttons.matching(identifier: "Workout.Finish.Confirm").firstMatch
        forceTap(finish)
        waitForIdentifier("Workout.Start")
        let recent = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Recent.'")).firstMatch
        waitFor(recent)
    }

    func testDataManagementOpensFromWorkout() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.addWorkout)

        openAddToolbarAction("Workout.Settings")
        // 2.2 moved Data & Backups behind the new Settings screen, below the
        // fold of a lazy List — it isn't in the tree until we scroll to it.
        scrollToElement(app.descendants(matching: .any).matching(identifier: "Settings.Data").firstMatch, in: app)
        forceTap(waitForIdentifier("Settings.Data", timeout: 10))
        waitForIdentifier("Data.Summary", timeout: 15)
        waitForIdentifier("Data.Export")
        waitForIdentifier("Data.Restore")
    }
}
