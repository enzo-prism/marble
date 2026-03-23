import SwiftData
import XCTest
@testable import marble

final class SplitSnapshotTests: SnapshotTestCase {
    func testSplitEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let emptyView = SplitView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(emptyView, named: "Split_Empty", testName: "testSplitStates")
    }

    func testSplitPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let populatedView = SplitView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(populatedView, named: "Split_Populated", testName: "testSplitStates")
    }
}
