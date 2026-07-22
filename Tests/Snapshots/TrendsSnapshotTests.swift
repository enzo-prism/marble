import SwiftData
import SwiftUI
import XCTest
@testable import marble

final class TrendsSnapshotTests: SnapshotTestCase {
    override func setUp() {
        super.setUp()
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        SharedDefaults.suite.set(DailyHighlightWindow.defaultStartMinute, forKey: SharedDefaults.Key.dailyHighlightsStartMinute)
        SharedDefaults.suite.set(DailyHighlightWindow.defaultEndMinute, forKey: SharedDefaults.Key.dailyHighlightsEndMinute)
    }

    override func tearDown() {
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsStartMinute)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsEndMinute)
        super.tearDown()
    }

    func testTrendsEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)

        let view = TrendsView()
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Empty")
    }

    func testTrendsPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = TrendsView()
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Populated")
    }

    func testTrendsDailyHighlights() {
        let calendar = Calendar.current
        TestHooks.overrideNow = calendar.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: SnapshotFixtures.now
        ) ?? SnapshotFixtures.now

        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let priorDay = calendar.date(byAdding: .day, value: -5, to: SnapshotFixtures.now) ?? SnapshotFixtures.now
        SnapshotFixtures.addSet(
            in: context,
            exerciseName: "Bench Press",
            performedAt: priorDay,
            weight: 175,
            reps: 5
        )
        SnapshotFixtures.addSet(
            in: context,
            exerciseName: "Bench Press",
            performedAt: SnapshotFixtures.now,
            weight: 205,
            reps: 5
        )

        let view = TrendsView()
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_DailyHighlights")
    }

    func testTrendsFilteredExercise() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let bench = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let view = TrendsView(initialExercise: bench)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
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
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_ConsistencyTooltip")
    }

    func testTrendsVolumeTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let weekStart = TrendsDateHelper.startOfWeek(for: SnapshotFixtures.now)
        let view = TrendsView(initialSelectedWeekStart: weekStart)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_VolumeTooltip")
    }

    func testTrendsSupplementsTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let creatine = SnapshotFixtures.supplementType(named: "Creatine", in: context)
        let view = TrendsView(initialSupplementType: creatine, initialSelectedSupplementDay: SnapshotFixtures.now)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
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
