import SwiftData
import XCTest
@testable import marble

@MainActor
final class WorkoutHistoryTests: MarbleTestCase {
    func testImportedOwnerNotesKeepJournalOrderInHistoryAndRepeatAfterReload() throws {
        let context = makeInMemoryContext()
        let draft = HandwrittenWorkoutParser.parseDetailed("""
            9/4/26
            Straight Leg Speed Bounds (2 sets)
            Knee Drive Speed Bounds (2 sets)
            Resistance Rope Sprint 2 sets , 50m each
            Sprints , 2 sets , 50m each
            """, referenceDate: now).draft
        try WorkoutScanImporter.import(draft, externalID: "owner-notes-order", source: .textEntry, in: context)

        // Reload relationships so this contract cannot accidentally depend on
        // SwiftData returning the importer's original insertion array.
        let reloaded = ModelContext(context.container)
        let session = try XCTUnwrap(reloaded.fetch(FetchDescriptor<WorkoutSession>()).first)
        let names = ["Straight Leg Speed Bounds", "Knee Drive Speed Bounds", "Resistance Rope Sprint", "Sprints"]
        let expectedSets = names.flatMap { [$0, $0] }
        let journal = try reloaded.fetch(FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        ))
        XCTAssertEqual(journal.map { $0.exercise.name }, expectedSets)
        XCTAssertEqual(WorkoutHistoryQuery.orderedEntries(for: session).map(\.id), journal.map(\.id))
        let repeated = WorkoutRepeatDraft.make(from: session, now: now)
        XCTAssertEqual(repeated.exercises.map(\.name), names)
        XCTAssertEqual(repeated.exercises.map { $0.sets.count }, [2, 2, 2, 2])
        XCTAssertEqual(repeated.exercises.suffix(2).flatMap(\.sets).map(\.distance), [50, 50, 50, 50])
        XCTAssertTrue(repeated.exercises.flatMap(\.sets).allSatisfy { $0.performedAt == nil })
    }

    func testImportedHistoryKeepsExplicitTimestampPrecedenceAndMixedSessionsChronological() throws {
        let context = makeInMemoryContext()
        let draft = ParsedWorkoutDraft(performedAt: now, title: "Timed import", exercises: [
            ParsedExerciseDraft(name: "Squat", sets: [ParsedSetDraft(reps: 5)]),
            ParsedExerciseDraft(name: "Row", sets: [ParsedSetDraft(reps: 8, performedAt: now.addingTimeInterval(60))])
        ])
        try WorkoutScanImporter.import(draft, externalID: "explicit-time-order", source: .photoScan, in: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(WorkoutHistoryQuery.orderedEntries(for: session).map { $0.exercise.name }, ["Row", "Squat"])
        XCTAssertEqual(WorkoutRepeatDraft.make(from: session, now: now).exercises.map(\.name), ["Row", "Squat"])

        let manual = SetEntry(exercise: session.entries[0].exercise, performedAt: now.addingTimeInterval(30), reps: 3, restAfterSeconds: 60)
        context.insert(manual)
        session.append(manual)
        XCTAssertEqual(WorkoutHistoryQuery.orderedEntries(for: session).map(\.id), session.orderedEntries.map(\.id))
    }

    func testSprintRepeatKeepsPrecisePreviousTimingInNotes() {
        let exercise = Exercise(name: "Sprint", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        let entry = SetEntry(exercise: exercise, performedAt: now, durationSeconds: 12, restAfterSeconds: 90, notes: "Flying start")
        let session = WorkoutSession(title: "Speed", startedAt: now, endedAt: now.addingTimeInterval(600), entries: [entry])
        let detail = SprintRepDetail(setEntryID: entry.id, durationTenths: 123, targetLowerTenths: 120, targetUpperTenths: 125)
        let draft = WorkoutRepeatDraft.make(from: session, now: now, sprintDetails: [entry.id: detail])
        let copied = draft.exercises[0].sets[0]
        XCTAssertEqual(copied.durationSeconds, 12)
        XCTAssertTrue(copied.notes?.contains("Flying start") == true)
        XCTAssertTrue(copied.notes?.contains(SprintTiming.text(tenths: 123)) == true)
        XCTAssertTrue(copied.notes?.contains(SprintTiming.text(tenths: 120)) == true)
        XCTAssertTrue(copied.notes?.contains(SprintTiming.text(tenths: 125)) == true)
        XCTAssertEqual(entry.notes, "Flying start")
        XCTAssertEqual(detail.durationTenths, 123)
    }

    func testRepeatCopiesEditableValuesAndPreservesCircuitOrderWithoutSaving() throws {
        let context = makeInMemoryContext()
        let squat = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        let row = Exercise(name: "Row", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        context.insert(squat)
        context.insert(row)
        let entries = [squat, row, squat].enumerated().map { index, exercise in
            SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(Double(index)), weight: 80,
                     weightUnit: .kg, reps: 5, difficulty: 7, restAfterSeconds: 90, notes: "Controlled")
        }
        entries.forEach { context.insert($0) }
        let session = WorkoutSession(title: "Circuit", startedAt: now, endedAt: now.addingTimeInterval(600), notes: "Keep form controlled", entries: entries)
        context.insert(session)
        try context.save()
        XCTAssertEqual(WorkoutHistoryQuery.orderedEntries(for: session).map(\.id), entries.map(\.id),
                       "Manual circuits keep ascending performance time in History")
        let today = now.addingTimeInterval(86_400)
        var draft = WorkoutRepeatDraft.make(from: session, now: today)
        XCTAssertEqual(draft.performedAt, today)
        XCTAssertEqual(draft.notes, "Keep form controlled")
        XCTAssertNil(draft.endedAt)
        XCTAssertNil(draft.durationSeconds)
        XCTAssertEqual(draft.exercises.map(\.libraryExerciseID), [squat.id, row.id, squat.id])
        XCTAssertEqual(draft.totalSetCount, 3)
        XCTAssertTrue(draft.exercises.flatMap(\.sets).allSatisfy { $0.performedAt == nil })
        XCTAssertEqual(draft.exercises[0].sets[0].weightUnit, .kg)
        XCTAssertEqual(draft.exercises[0].sets[0].difficulty, 7)
        XCTAssertEqual(draft.exercises[0].sets[0].restSeconds, 90)
        XCTAssertEqual(draft.exercises[0].sets[0].notes, "Controlled")
        draft.exercises[0].sets[0].weight = 100
        XCTAssertEqual(entries[0].weight, 80)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepeatCombinesConsecutiveSetsButKeepsDistinctExerciseIDs() {
        let first = Exercise(name: "Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        let second = Exercise(name: "Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        let entries = [first, first, second].enumerated().map { index, exercise in
            SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(Double(index)), reps: 8, restAfterSeconds: 60)
        }
        let session = WorkoutSession(title: "Push", startedAt: now, entries: entries)
        let draft = WorkoutRepeatDraft.make(from: session, now: now)
        XCTAssertEqual(draft.exercises.count, 2)
        XCTAssertEqual(draft.exercises.map { $0.sets.count }, [2, 1])
        XCTAssertEqual(draft.exercises.map(\.libraryExerciseID), [first.id, second.id])
        XCTAssertNotEqual(draft.exercises[0].sets[0].id, entries[0].id)
    }

    func testHistoryQueryFiltersAndPaginatesOnSQLite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: MarbleSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let exercise = Exercise(name: "Décline Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 60)
        context.insert(exercise)
        for index in 0..<45 {
            let date = now.addingTimeInterval(Double(-index) * 86_400)
            let entry = SetEntry(exercise: exercise, performedAt: date, reps: 8, restAfterSeconds: 60)
            context.insert(entry)
            context.insert(WorkoutSession(title: "Push \(index)", startedAt: date, endedAt: date.addingTimeInterval(60), entries: [entry]))
        }
        context.insert(WorkoutSession(title: "Active Push", startedAt: now))
        try context.save()
        let first = try context.fetch(WorkoutHistoryQuery.descriptor(search: "", day: nil))
        XCTAssertEqual(first.count, 41, "Only one sentinel beyond the visible page is fetched")
        let next = try context.fetch(WorkoutHistoryQuery.descriptor(search: "", day: nil, offset: 40))
        XCTAssertEqual(next.count, 5)
        XCTAssertTrue(Set(first.prefix(40).map(\.id)).isDisjoint(with: next.map(\.id)))
        XCTAssertEqual(try context.fetch(WorkoutHistoryQuery.descriptor(search: " push 0 ", day: nil)).count, 1)
        XCTAssertEqual(try context.fetch(WorkoutHistoryQuery.descriptor(search: "DECLINE", day: now)).count, 1)
        XCTAssertTrue(try context.fetch(WorkoutHistoryQuery.descriptor(search: "squat", day: nil)).isEmpty)
    }
}
