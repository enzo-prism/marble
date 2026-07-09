import SwiftData
import XCTest
@testable import marble

@MainActor
final class WorkoutSessionTests: MarbleTestCase {
    func testAppendOrdersSetsAndPreventsDuplicates() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let later = SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(60), reps: 5, restAfterSeconds: 120)
        let earlier = SetEntry(exercise: exercise, performedAt: now, reps: 5, restAfterSeconds: 120)
        let session = WorkoutSession(title: "Leg Day", startedAt: now)
        context.insert(exercise)
        context.insert(later)
        context.insert(earlier)
        context.insert(session)

        session.append(later)
        session.append(earlier)
        session.append(earlier)

        XCTAssertEqual(session.entries.count, 2)
        XCTAssertEqual(session.orderedEntries.map(\.id), [earlier.id, later.id])
        XCTAssertTrue(session.isActive)
    }

    func testFinishPersistsSessionWithoutDeletingSets() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(name: "Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        let entry = SetEntry(exercise: exercise, performedAt: now, weight: 185, reps: 5, restAfterSeconds: 90)
        let session = WorkoutSession(title: "Push", startedAt: now.addingTimeInterval(-1800), entries: [entry])
        context.insert(exercise)
        context.insert(entry)
        context.insert(session)
        session.finish(at: now)
        try context.save()

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(Int(session.duration), 1800)
        context.delete(session)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)
    }
}
