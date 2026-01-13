import SwiftData
import XCTest
@testable import marble

final class AddSetSnapshotTests: SnapshotTestCase {
    func testAddSetWeightAndReps() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let bench = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let view = AddSetView(initialPerformedAt: SnapshotFixtures.now, initialExercise: bench)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "AddSet_WeightReps")
    }

    func testAddSetRepsOnlyAddedLoadOff() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let pushUps = SnapshotFixtures.exercise(named: "Push Ups", in: context)
        let view = AddSetView(initialPerformedAt: SnapshotFixtures.now, initialExercise: pushUps)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "AddSet_RepsOnly_AddedLoadOff")
    }

    func testAddSetRepsOnlyAddedLoadOn() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        SnapshotFixtures.addSet(in: context, exerciseName: "Push Ups", performedAt: SnapshotFixtures.now, weight: 35, reps: 12, difficulty: 7, restAfterSeconds: 60)
        let pushUps = SnapshotFixtures.exercise(named: "Push Ups", in: context)

        let view = AddSetView(initialPerformedAt: SnapshotFixtures.now, initialExercise: pushUps)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "AddSet_RepsOnly_AddedLoadOn")
    }

    func testAddSetDurationOnly() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let plank = SnapshotFixtures.exercise(named: "Plank", in: context)
        let view = AddSetView(initialPerformedAt: SnapshotFixtures.now, initialExercise: plank)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "AddSet_DurationOnly")
    }
}
