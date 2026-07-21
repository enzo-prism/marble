import XCTest

final class WorkoutFlowUITests: MarbleUITestCase {
    func testWorkoutSupportsLargestAccessibilityText() {
        launchApp(
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            fixtureMode: "populated"
        )
        navigateToTab(.split)

        let start = waitForIdentifier("Workout.Start", timeout: 8)
        XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThan(start.frame.height, 80, "The primary action should grow to fit its wrapped label")

        let list = app.descendants(matching: .any).matching(identifier: "Workout.List").firstMatch
        let editPlan = app.descendants(matching: .any).matching(identifier: "Workout.EditPlan").firstMatch
        scrollToElement(editPlan, in: list)
        waitFor(editPlan)
        XCTAssertTrue(editPlan.isHittable)
        XCTAssertGreaterThan(editPlan.frame.height, 44)
    }

    func testStartAndFinishWorkout() {
        launchApp(fixtureMode: "empty")
        navigateToTab(.split)

        forceTap(waitForIdentifier("Workout.Start", timeout: 8))
        forceTap(waitForIdentifier("Workout.AddSet"))
        selectExercise(identifier: "BenchPress")
        let weightField = textInput("AddSet.Weight")
        waitFor(weightField)
        clearAndType(weightField, text: "135")
        dismissKeyboardIfPresent()
        forceTap(revealAddSetSaveButton())
        waitForDisappearance(app.navigationBars["Log Set"], timeout: 6)
        let workoutSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Set.'"))
            .firstMatch
        waitFor(workoutSet, timeout: 8)

        forceTap(waitForIdentifier("Workout.Finish"))

        let finish = app.buttons.matching(identifier: "Workout.Finish.Confirm").firstMatch
        forceTap(finish)
        waitForIdentifier("Workout.Start")
        let recent = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'Workout.Recent.'")).firstMatch
        waitFor(recent)
    }

    func testDataManagementOpensFromWorkout() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.split)

        forceTap(waitForIdentifier("Workout.Data"))
        // 2.2 moved Data & Backups behind the new Settings screen, below the
        // fold of a lazy List — it isn't in the tree until we scroll to it.
        scrollToElement(app.descendants(matching: .any).matching(identifier: "Settings.Data").firstMatch, in: app)
        forceTap(waitForIdentifier("Settings.Data", timeout: 10))
        waitForIdentifier("Data.Summary", timeout: 15)
        waitForIdentifier("Data.Export")
        waitForIdentifier("Data.Restore")
    }
}
