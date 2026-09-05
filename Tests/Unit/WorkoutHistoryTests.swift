import SwiftData
import XCTest
@testable import marble

@MainActor
final class WorkoutHistoryTests: MarbleTestCase {
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
