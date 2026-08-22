import SwiftData
import XCTest
@testable import marble

@MainActor
final class SupplementsSnapshotTests: SnapshotTestCase {
    func testSupplementsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = SupplementsView()
            .modelContainer(container)
            .environment(QuickLogCoordinator())
            .environment(makeTabSelection(.supplements))
        assertSnapshot(view, named: "Supplements_Empty")
    }

    func testSupplementsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = SupplementsView()
            .modelContainer(container)
            .environment(QuickLogCoordinator())
            .environment(makeTabSelection(.supplements))
        assertSnapshot(view, named: "Supplements_Populated")
    }
}
