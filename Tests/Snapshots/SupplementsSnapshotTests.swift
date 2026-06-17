import SwiftData
import SwiftUI
import XCTest
@testable import marble

final class SupplementsSnapshotTests: SnapshotTestCase {
    func testSupplementsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = SupplementsView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Supplements_Empty")
    }

    func testSupplementsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = SupplementsView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Supplements_Populated")
    }

    func testSupplementTypeEditorWithCustomEmoji() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        let type = SupplementType(name: "Protein Powder", defaultDose: 1, unit: .scoop, isFavorite: true, customIconEmoji: "🥤")
        context.insert(type)
        try? context.save()

        let view = NavigationStack {
            SupplementTypeEditorView(type: type)
        }
        .modelContainer(container)
        assertSnapshot(view, named: "SupplementTypeEditor_Emoji")
    }
}
