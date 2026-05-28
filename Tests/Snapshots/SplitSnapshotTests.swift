import SwiftData
import SwiftUI
import XCTest
@testable import marble

final class SplitSnapshotTests: SnapshotTestCase {
    func testSplitEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let emptyView = NavigationStack {
            SplitView()
        }
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(emptyView, named: "Split_Empty", testName: "testSplitStates")
    }

    func testSplitPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let populatedView = NavigationStack {
            SplitView()
        }
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(populatedView, named: "Split_Populated", testName: "testSplitStates")
    }
}
