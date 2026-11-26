import SwiftUI
import XCTest
@testable import marble

@MainActor
final class ExerciseEditorSnapshotTests: SnapshotTestCase {
    func testNewExercise() {
        let view = ExerciseEditorView(exercise: nil)
            .modelContainer(SnapshotFixtures.makeContainer())
        assertSnapshot(view, named: "NewExercise")
    }

    func testDuplicateName() {
        let container = SnapshotFixtures.makeContainer()
        SnapshotFixtures.seedBase(in: container.mainContext)
        let view = ExerciseEditorView(exercise: nil, initialName: "Bench Press")
            .modelContainer(container)
        assertSnapshot(view, named: "NewExercise_Duplicate")
    }

    func testTrackingTypes() {
        let view = NavigationStack {
            ExerciseTrackingPicker(selection: .strength) { _ in }
        }
        assertSnapshot(view, named: "TrackingTypes")
    }
}
