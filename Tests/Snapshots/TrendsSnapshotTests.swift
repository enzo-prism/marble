import SwiftData
import XCTest
@testable import marble

final class TrendsSnapshotTests: SnapshotTestCase {
    func testTrendsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = TrendsView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Empty")
    }

    func testTrendsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = TrendsView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Populated")
    }

    func testTrendsFilteredExercise() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let bench = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let view = TrendsView(initialExercise: bench)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Filtered")
    }

    func testTrendsConsistencyTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = TrendsView(initialSelectedDay: SnapshotFixtures.now)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_ConsistencyTooltip")
    }

    func testTrendsVolumeTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let weekStart = TrendsDateHelper.startOfWeek(for: SnapshotFixtures.now)
        let view = TrendsView(initialSelectedWeekStart: weekStart)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_VolumeTooltip")
    }
}
