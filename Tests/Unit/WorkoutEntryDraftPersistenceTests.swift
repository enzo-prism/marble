import SwiftData
import XCTest
@testable import marble

@MainActor
final class WorkoutEntryDraftPersistenceTests: MarbleTestCase {
    private final class Store: WorkoutEntryDraftStoring {
        enum Failure: Error { case unavailable }
        var value: WorkoutEntryDraft?
        var failSave = false
        var failLoad = false
        func load() throws -> WorkoutEntryDraft? {
            if failLoad { throw Failure.unavailable }
            return value
        }
        func save(_ draft: WorkoutEntryDraft) throws {
            if failSave { throw Failure.unavailable }
            value = draft
        }
        func clear() throws { value = nil }
    }

    private func model(_ store: Store) -> WorkoutTextEntryViewModel {
        WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
    }

    func testRestoresCorrectedReviewAndExactImportIdentity() async throws {
        let store = Store()
        let context = makeInMemoryContext()
        let first = model(store)
        first.text = "Bench Press 3x8 @ 185"
        await first.preview(in: context)
        first.draft.exercises[0].sets[0].weight = 195
        first.draft.exercises[0].sets[0].notes = "Corrected after review"
        first.draft.performedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let libraryID = UUID()
        first.choose(.library(id: libraryID, name: "Barbell Bench Press"), for: first.draft.exercises[0].id)
        first.saveDraftNow()
        // Real encoding preserves nested values and UUID dictionary keys.
        store.value = try JSONDecoder().decode(WorkoutEntryDraft.self, from: JSONEncoder().encode(XCTUnwrap(store.value)))

        let restored = model(store)
        XCTAssertTrue(restored.hasRestoredDraft)
        XCTAssertEqual(restored.phase, .review)
        XCTAssertEqual(restored.draft, first.draft)
        XCTAssertEqual(restored.externalID, first.externalID)
        XCTAssertEqual(restored.resolutions, first.resolutions)
        restored.resumeDraft(in: context)
        XCTAssertFalse(restored.hasRestoredDraft)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
    }

    func testBatchSelectionAndOpenSessionEditsSurviveRelaunch() async {
        let store = Store()
        let first = model(store)
        first.text = "Monday: Push\nBench Press 3x8 @ 185\n\nTuesday: Pull\nBarbell Row 3x8 @ 135"
        await first.preview(in: makeInMemoryContext())
        XCTAssertEqual(first.sessions.count, 2)
        guard first.sessions.count == 2 else { return }
        first.toggleSessionSelected(first.sessions[1].id)
        first.openSession(first.sessions[0].id)
        first.draft.exercises[0].sets[0].reps = 12
        first.saveDraftNow()
        let restored = model(store)
        XCTAssertEqual(restored.sessions, first.sessions)
        XCTAssertEqual(restored.draft.exercises[0].sets[0].reps, 12)
        XCTAssertEqual(restored.reviewingSessionID, first.reviewingSessionID)
        XCTAssertFalse(restored.sessions[1].selected)
    }

    func testFailedSaveRetainsPreviousDraftAndCanRetry() {
        let store = Store()
        let first = model(store)
        first.text = "Bench 3x8"
        first.saveDraftNow()
        store.failSave = true
        first.text = "Bench 4x8"
        first.saveDraftNow()
        XCTAssertNotNil(first.draftStorageMessage)
        XCTAssertEqual(store.value?.text, "Bench 3x8")
        store.failSave = false
        first.saveDraftNow()
        XCTAssertNil(first.draftStorageMessage)
        XCTAssertEqual(store.value?.text, "Bench 4x8")
    }

    func testUnreadableDraftIsNotOverwritten() {
        let store = Store()
        store.failLoad = true
        let first = model(store)
        first.text = "New workout"
        first.saveDraftNow()
        XCTAssertNil(store.value)
        XCTAssertNotNil(first.draftStorageMessage)
    }

    func testCommitDoesNotImportWhenDraftIdentityCannotBeSaved() async {
        let store = Store()
        let context = makeInMemoryContext()
        var importCalls = 0
        let first = WorkoutTextEntryViewModel(
            parser: HeuristicWorkoutScanParser(),
            importHandler: { _, _, _ in
                importCalls += 1
                return WorkoutImporter.Summary()
            },
            draftStore: store
        )
        first.text = "Bench Press 3x8 @ 185"
        await first.preview(in: context)
        store.failSave = true
        first.commit(into: context)
        XCTAssertEqual(importCalls, 0)
        XCTAssertEqual(first.phase, .review)
        XCTAssertNotNil(first.errorMessage)
        XCTAssertNotNil(first.draftStorageMessage)
    }

    func testSuccessfulCommitClearsDraftAndReplayDoesNotDuplicate() async throws {
        let store = Store()
        let context = makeInMemoryContext()
        let first = model(store)
        first.text = "Bench Press 3x8 @ 185"
        await first.preview(in: context)
        first.saveDraftNow()
        let preCommit = store.value
        first.commit(into: context)
        XCTAssertEqual(first.phase, .imported)
        XCTAssertNil(store.value)
        let count = try context.fetchCount(FetchDescriptor<SetEntry>())
        XCTAssertEqual(count, 3)
        // Simulate termination between database commit and clearing the file.
        store.value = preCommit
        let replay = model(store)
        replay.commit(into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), count)
        XCTAssertNil(store.value)
    }

    func testDiscardClearsAndRepeatPreservesLibraryIdentity() {
        let store = Store()
        let first = model(store)
        let exerciseID = UUID()
        let draft = ParsedWorkoutDraft(title: "Repeat", exercises: [ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(reps: 8)], libraryExerciseID: exerciseID)])
        first.startReview(with: draft)
        let restored = model(store)
        XCTAssertEqual(restored.draft, first.draft)
        XCTAssertEqual(restored.externalID, first.externalID)
        XCTAssertEqual(restored.resolution(for: draft.exercises[0].id)?.choice, .library(id: exerciseID, name: "Bench"))
        restored.reset()
        XCTAssertNil(store.value)
    }

    func testClearingLastWeightKeepsFieldAvailableAfterRecovery() async {
        let store = Store()
        let first = model(store)
        first.text = "Bench Press 1x8 @ 185"
        await first.preview(in: makeInMemoryContext())
        first.draft.exercises[0].sets[0].weight = nil
        XCTAssertTrue(first.draft.exercises[0].metricsProfile.usesWeight)
        first.saveDraftNow()
        let restored = model(store)
        XCTAssertNil(restored.draft.exercises[0].sets[0].weight)
        XCTAssertTrue(restored.draft.exercises[0].metricsProfile.usesWeight)
    }
}
