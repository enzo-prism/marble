import XCTest
@testable import marble

@MainActor
final class TabSelectionTests: XCTestCase {
    func testAddWorkoutIsTheDefaultDestination() {
        let selection = TabSelection()

        XCTAssertEqual(selection.selected, .addWorkout)
        XCTAssertEqual(selection.tabBarSelection, .addWorkout)
    }

    func testReturningToLogRestoresItsLastMode() {
        let selection = TabSelection()
        selection.selectLogMode(.calendar)
        selection.selected = .addWorkout

        selection.tabBarSelection = .journal

        XCTAssertEqual(selection.selected, .calendar)
    }

    func testPendingWorkoutTextIsConsumedOnlyOnce() {
        _ = PendingTextImport.consume()
        PendingTextImport.stage("Bench 3x8")

        XCTAssertEqual(PendingTextImport.consume(), "Bench 3x8")
        XCTAssertNil(PendingTextImport.consume())
    }
}
