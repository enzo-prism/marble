import SwiftData
import SwiftUI
import XCTest
@testable import marble

final class EmpireSnapshotTests: SnapshotTestCase {
    func testEmpireEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = EmpireView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Empire_Empty")
    }

    func testEmpirePopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let built = ["quarry", "altar", "column", "agora", "temple"]
        let spent = built.compactMap { EmpireEconomy.structure(id: $0)?.cost }.reduce(0, +)
        let state = EmpireState(
            spentTalents: spent,
            storedLifetimeTalents: 0,
            builtStructureRaw: built.joined(separator: "\n"),
            createdAt: SnapshotFixtures.now,
            updatedAt: SnapshotFixtures.now
        )
        context.insert(state)
        try? context.save()

        let view = EmpireView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Empire_Populated")
    }

    func testEmpireTributeClaimed() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let built = ["quarry", "altar", "column", "agora", "temple"]
        let spent = built.compactMap { EmpireEconomy.structure(id: $0)?.cost }.reduce(0, +)
        // A mid-progress Tribute state: claimed today, a 12-day streak with reprieves banked, and a
        // handful of relics collected (so the claimed card, skyline relics, and gallery all render).
        let state = EmpireState(
            spentTalents: spent,
            storedLifetimeTalents: 0,
            bonusTalents: 4_200,
            builtStructureRaw: built.joined(separator: "\n"),
            lastTributeDay: EmpireTribute.tributeDay(for: SnapshotFixtures.now),
            tributeStreak: 12,
            longestTributeStreak: 12,
            streakFreezes: 2,
            collectedRelicsRaw: ["olive", "laurel", "shield", "sundisc"].joined(separator: "\n"),
            claimedMilestonesRaw: "7",
            createdAt: SnapshotFixtures.now,
            updatedAt: SnapshotFixtures.now
        )
        context.insert(state)
        try? context.save()

        let view = EmpireView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Empire_TributeClaimed")
    }
}
