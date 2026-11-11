import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class TrendsSnapshotTests: SnapshotTestCase {
    override func setUp() {
        super.setUp()
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        SharedDefaults.suite.set(DailyHighlightWindow.defaultStartMinute, forKey: SharedDefaults.Key.dailyHighlightsStartMinute)
        SharedDefaults.suite.set(DailyHighlightWindow.defaultEndMinute, forKey: SharedDefaults.Key.dailyHighlightsEndMinute)
        SharedDefaults.suite.set(WeightUnit.lb.rawValue, forKey: SharedDefaults.Key.preferredWeightUnit)
    }

    override func tearDown() {
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsStartMinute)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.dailyHighlightsEndMinute)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Key.preferredWeightUnit)
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
        assertSnapshot(
            view,
            named: "Trends_Populated",
            variants: SnapshotMatrix.regularWidthVariants
        )
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

        let view = TrendsView(initiallyShowsDetails: true)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_DailyHighlights")
    }

    func testTrendsDetails() {
        SharedDefaults.suite.set(false, forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        let container = SnapshotFixtures.makeContainer()
        SnapshotFixtures.seedPopulated(in: ModelContext(container))
        let view = TrendsView(prioritizesInitialDetail: true)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_Details")
    }

    func testTrendsCategoryCharts() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)
        let entries = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        let groups: [LifterCoaching.MuscleGroupCoverage] = [
            .init(category: .chest, setsPerWeek: 12, directSets: 12, indirectSets: 0, lastTrainedDaysAgo: 0, band: .inRange),
            .init(category: .back, setsPerWeek: 8, directSets: 8, indirectSets: 0, lastTrainedDaysAgo: 2, band: .below),
            .init(category: .quads, setsPerWeek: 16, directSets: 16, indirectSets: 0, lastTrainedDaysAgo: 1, band: .inRange)
        ]
        assertSnapshot(TrendsCategoryChartsFixture(groups: groups, buckets: []), named: "Trends_MuscleGroups")
        assertSnapshot(TrendsCategoryChartsFixture(groups: [], buckets: LifterAnalytics.repRangeDistribution(entries: entries)), named: "Trends_RepRanges")
    }

    func testTrendsFilteredExercise() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let bench = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let view = TrendsView(initialExercise: bench, prioritizesInitialDetail: true)
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

        let view = TrendsView(initialSelectedDay: SnapshotFixtures.now, prioritizesInitialDetail: true)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_ConsistencyTooltip")
    }

    func testTrendsVolumeTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let weekStart = TrendsDateHelper.startOfWeek(for: SnapshotFixtures.now)
        let view = TrendsView(initialSelectedWeekStart: weekStart, prioritizesInitialDetail: true)
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_VolumeTooltip")
    }

    func testTrendsSupplementsTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let creatine = SnapshotFixtures.supplementType(named: "Creatine", in: context)
        let view = TrendsView(
            initialSupplementType: creatine,
            initialSelectedSupplementDay: SnapshotFixtures.now,
            prioritizesInitialDetail: true
        )
            .modelContainer(container)
            .environment(QuickLogCoordinator())
        assertSnapshot(view, named: "Trends_SupplementsTooltip")
    }
}

private struct TrendsCategoryChartsFixture: View {
    let groups: [LifterCoaching.MuscleGroupCoverage]
    let buckets: [LifterAnalytics.RepRangeBucket]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxl) {
                ProgressDetailHeading(section: .training)
                if !groups.isEmpty {
                    MuscleGroupSectionView(groups: groups, accessibilityValue: "Three muscle groups")
                }
                if !buckets.isEmpty {
                    RepRangeSectionView(buckets: buckets)
                }
            }
            .padding(MarbleLayout.pagePadding)
        }
        .background(Theme.backgroundColor(for: colorScheme))
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
