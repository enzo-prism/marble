import SwiftData
import SwiftUI
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

    func testTrendsExerciseSearch() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let bench = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt, order: .reverse)]))) ?? []
        let view = TrendsExerciseSearchFixture(
            exercises: exercises,
            entries: entries,
            initialSelection: bench.id
        )
            .modelContainer(container)

        assertSnapshot(view, named: "Trends_ExerciseSearch")
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

    func testTrendsSupplementsTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let creatine = SnapshotFixtures.supplementType(named: "Creatine", in: context)
        let view = TrendsView(initialSupplementType: creatine, initialSelectedSupplementDay: SnapshotFixtures.now)
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_SupplementsTooltip")
    }
}

private struct TrendsExerciseSearchFixture: View {
    let exercises: [Exercise]
    let entries: [SetEntry]
    @State private var selectedExerciseID: UUID?

    init(exercises: [Exercise], entries: [SetEntry], initialSelection: UUID?) {
        self.exercises = exercises
        self.entries = entries
        _selectedExerciseID = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            TrendsExerciseSearchView(
                exercises: exercises,
                entries: entries,
                selectedExerciseID: $selectedExerciseID
            )
        }
    }
}
