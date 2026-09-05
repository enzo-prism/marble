import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class WorkoutComposerSnapshotTests: SnapshotTestCase {
    private final class DraftStore: WorkoutEntryDraftStoring {
        var value: WorkoutEntryDraft?
        func load() throws -> WorkoutEntryDraft? { value }
        func save(_ draft: WorkoutEntryDraft) throws { value = draft }
        func clear() throws { value = nil }
    }

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

    func testWorkoutComposerRecoveredReview() throws {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        let store = DraftStore()
        let original = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        original.startReview(with: ParsedWorkoutDraft(
            performedAt: SnapshotFixtures.now.addingTimeInterval(-86_400),
            title: "Push day",
            exercises: [ParsedExerciseDraft(name: "Bench Press", sets: [ParsedSetDraft(weight: 195, reps: 8)])]
        ))
        // The recovery screen is driven by the same encoded draft as relaunch.
        store.value = try JSONDecoder().decode(WorkoutEntryDraft.self, from: JSONEncoder().encode(XCTUnwrap(store.value)))
        let recovered = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        XCTAssertTrue(recovered.hasRestoredDraft)
        XCTAssertEqual(recovered.phase, .review)
        assertSnapshot(
            composer(viewModel: recovered, container: container),
            named: "WorkoutComposer_RecoveredReview"
        )
    }

    func testWorkoutComposerCorrectedWeightAfterRecovery() throws {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedBase(in: context)
        let store = DraftStore()
        let original = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        original.startReview(with: ParsedWorkoutDraft(
            performedAt: SnapshotFixtures.now,
            title: "Push day",
            exercises: [ParsedExerciseDraft(name: "Bench Press", sets: [ParsedSetDraft(weight: 185, reps: 8)])]
        ))
        // A cleared optional number must keep its editor alive long enough to
        // enter the replacement, including across draft persistence.
        original.draft.exercises[0].sets[0].weight = nil
        XCTAssertTrue(original.draft.exercises[0].metricsProfile.usesWeight)
        XCTAssertTrue(original.saveDraftNow())
        store.value = try JSONDecoder().decode(WorkoutEntryDraft.self, from: JSONEncoder().encode(XCTUnwrap(store.value)))
        let recovered = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        recovered.resumeDraft(in: context)
        XCTAssertTrue(recovered.draft.exercises[0].metricsProfile.usesWeight)
        recovered.draft.exercises[0].sets[0].weight = 195
        XCTAssertEqual(recovered.draft.exercises[0].sets[0].id, original.draft.exercises[0].sets[0].id)
        assertSnapshot(
            composer(viewModel: recovered, container: container),
            named: "WorkoutComposer_CorrectedWeightAfterRecovery"
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
        // Native date pickers otherwise inherit the runner's regional settings.
        .environment(\.locale, Locale(identifier: "en_US"))
    }
}
