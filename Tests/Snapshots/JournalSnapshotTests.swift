import SwiftData
import XCTest
@testable import marble

final class JournalSnapshotTests: SnapshotTestCase {
    func testJournalEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let view = JournalView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Journal_Empty")
    }

    func testJournalPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        SnapshotFixtures.addSet(in: context, exerciseName: "Bench Press", performedAt: SnapshotFixtures.now, weight: 185, reps: 5, difficulty: 8, restAfterSeconds: 90)
        SnapshotFixtures.addSet(in: context, exerciseName: "Push Ups", performedAt: SnapshotFixtures.now, weight: nil, reps: 20, difficulty: 6, restAfterSeconds: 60)

        let view = JournalView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Journal_Populated")
    }

    func testJournalLongName() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        SnapshotFixtures.addSet(in: context, exerciseName: "Single Arm Dumbbell Bulgarian Split Squat (Paused)", performedAt: SnapshotFixtures.now, weight: 95, reps: 8, difficulty: 7, restAfterSeconds: 120)

        let view = JournalView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Journal_LongName")
    }

    func testJournalExtremes() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        SnapshotFixtures.addSet(in: context, exerciseName: "Bench Press", performedAt: SnapshotFixtures.now, weight: 999.5, reps: 999, difficulty: 10, restAfterSeconds: 999)
        SnapshotFixtures.addSet(in: context, exerciseName: "Sauna", performedAt: SnapshotFixtures.now, weight: nil, reps: nil, durationSeconds: 9999, difficulty: 1, restAfterSeconds: 0)

        let view = JournalView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Journal_Extremes")
    }

    func testQuickLogVisible() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        SnapshotFixtures.addSet(in: context, exerciseName: "Bench Press", performedAt: SnapshotFixtures.now, weight: 185, reps: 5, difficulty: 8, restAfterSeconds: 90)

        let view = ContentView()
            .modelContainer(container)
        assertSnapshot(view, named: "Journal_QuickLog")
    }
}
