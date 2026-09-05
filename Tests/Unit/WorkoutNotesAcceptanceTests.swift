import SwiftData
import XCTest
@testable import marble

/// Acceptance of an actual Notes paste, through review, recovery, and persistence.
/// Every effort is checked, including values the user deliberately did not supply.
@MainActor
final class WorkoutNotesAcceptanceTests: MarbleTestCase {
    private let note = """
        9/4/26

        Straight Leg Speed Bounds (2 sets)

        Knee Drive Speed Bounds (2 sets)

        Resistance Rope Sprint 2 sets , 50m each

        Sprints , 2 sets , 50m each
        """

    private final class Store: WorkoutEntryDraftStoring {
        var value: WorkoutEntryDraft?
        func load() throws -> WorkoutEntryDraft? { value }
        func save(_ draft: WorkoutEntryDraft) throws { value = draft }
        func clear() throws { value = nil }
    }

    func testNotesWorkoutSurvivesReviewRecoveryAndSavesEightExactEfforts() async throws {
        let context = makeInMemoryContext()
        let store = Store()
        let first = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        first.text = note
        await first.preview(in: context)

        XCTAssertEqual(first.phase, .review)
        XCTAssertEqual(first.draft.totalSetCount, 8)
        XCTAssertTrue(first.unparsedLines.isEmpty)
        let names = ["Straight Leg Speed Bounds", "Knee Drive Speed Bounds", "Resistance Rope Sprint", "Sprints"]
        XCTAssertEqual(first.draft.exercises.map(\.name), names)
        XCTAssertFalse(names.contains(first.draft.title), "An exercise is not the workout title")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0, "Preview must never log anything")
        XCTAssertTrue(first.saveDraftNow())
        let saved = try XCTUnwrap(store.value)
        store.value = try JSONDecoder().decode(WorkoutEntryDraft.self, from: JSONEncoder().encode(saved))

        let restored = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        XCTAssertEqual(restored.draft, first.draft)
        restored.resumeDraft(in: context)
        restored.commit(into: context)
        XCTAssertEqual(restored.phase, .imported)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(entries.count, 8)
        let expectedDate = try XCTUnwrap(Self.stableCalendar.date(from: DateComponents(year: 2026, month: 9, day: 4)))
        for (index, name) in names.enumerated() {
            let efforts = entries.filter { $0.exercise.name == name }
            XCTAssertEqual(efforts.count, 2, name)
            for effort in efforts {
                XCTAssertNil(effort.reps, name)
                XCTAssertNil(effort.weight, name)
                XCTAssertNil(effort.durationSeconds, name)
                XCTAssertEqual(Self.stableCalendar.startOfDay(for: effort.performedAt), expectedDate)
                if index < 2 {
                    XCTAssertNil(effort.distance, name)
                    XCTAssertFalse(effort.exercise.metrics.repsIsRequired)
                    XCTAssertTrue(SetRowView.accessibilitySummary(for: effort).contains("Set recorded"))
                } else {
                    XCTAssertEqual(effort.distance, 50, name)
                    XCTAssertEqual(effort.distanceUnit, .meters)
                }
            }
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.entries.count, 8)
        XCTAssertNil(store.value)

        // Replaying the saved pre-commit draft must not duplicate the workout.
        store.value = saved
        let replay = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), draftStore: store)
        replay.commit(into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 8)
    }

    func testCountOnlyDraftKeepsOptionalMetricsThroughCoding() throws {
        let draft = ParsedExerciseDraft(name: "Bounds", sets: [ParsedSetDraft(), ParsedSetDraft()])
        XCTAssertEqual(draft.metricsProfile.reps, .optional)
        XCTAssertFalse(draft.metricsProfile.usesWeight)
        XCTAssertFalse(draft.metricsProfile.usesDistance)
        let restored = try JSONDecoder().decode(ParsedExerciseDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertTrue(restored.sets.allSatisfy { !$0.hasAnyValue })
    }
}
