import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class WorkoutComposerSnapshotTests: SnapshotTestCase {
    func testWorkoutComposerEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        let viewModel = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser())

        assertSnapshot(
            composer(viewModel: viewModel, container: container),
            named: "WorkoutComposer_Empty"
        )
        assertSnapshot(
            composer(viewModel: viewModel, container: container),
            named: "WorkoutComposer_Empty",
            variants: SnapshotMatrix.regularWidthVariants
        )
    }

    func testWorkoutComposerLivePreview() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        let viewModel = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser())
        viewModel.text = "Bench Press 3x8 @ 185 lb\nFelt strong today"
        viewModel.updateLivePreview()

        assertSnapshot(
            composer(viewModel: viewModel, container: container),
            named: "WorkoutComposer_LivePreview"
        )
    }

    func testWorkoutComposerReview() async {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        let viewModel = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser())
        viewModel.text = "Push day\nBench Press 3x8 @ 185 lb rest 90s\nPlank 3x45s"
        await viewModel.preview(in: context)

        assertSnapshot(
            composer(viewModel: viewModel, container: container),
            named: "WorkoutComposer_Review"
        )
    }

    private func composer(
        viewModel: WorkoutTextEntryViewModel,
        container: ModelContainer
    ) -> some View {
        WorkoutTextEntryView(
            viewModel: viewModel,
            presentation: .primaryTab,
            onShowJournal: {},
            prewarmsModel: false
        )
        .modelContainer(container)
        .environment(QuickLogCoordinator())
    }
}
