import SwiftData
import XCTest
@testable import marble

final class SupplementsSnapshotTests: SnapshotTestCase {
    func testSupplementsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = SupplementsView()
            .modelContainer(container)
        assertSnapshot(view, named: "Supplements_Empty")
    }

    func testSupplementsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = SupplementsView()
            .modelContainer(container)
        assertSnapshot(view, named: "Supplements_Populated")
    }
}

