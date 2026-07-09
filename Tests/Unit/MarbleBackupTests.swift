import SwiftData
import XCTest
@testable import marble

@MainActor
final class MarbleBackupTests: MarbleTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "persistenceLastSuccessfulRestore")
        super.tearDown()
    }

    func testBackupRoundTripRestoresCoreTrainingDataAndRelationships() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Deadlift", category: .back, metrics: .weightAndRepsRequired, defaultRestSeconds: 180)
        let entry = SetEntry(exercise: exercise, performedAt: now, weight: 315, reps: 5, restAfterSeconds: 180)
        let session = WorkoutSession(title: "Pull", startedAt: now.addingTimeInterval(-1200), endedAt: now, entries: [entry])
        let type = SupplementType(name: "Creatine", defaultDose: 5, unit: .g, isFavorite: true)
        let supplement = SupplementEntry(type: type, takenAt: now, dose: 5, unit: .g)
        source.insert(exercise)
        source.insert(entry)
        source.insert(session)
        source.insert(type)
        source.insert(supplement)
        try source.save()

        let document = try MarbleBackupService.makeDocument(in: source, now: now)
        let summary = try MarbleBackupService.inspect(data: document.data)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.supplementLogs, 1)

        let destination = makeInMemoryContext()
        let firstRestore = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(firstRestore.sets, 1)
        XCTAssertEqual(firstRestore.sessions, 1)

        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SupplementEntry>()), 1)
        let restoredSession = try XCTUnwrap(destination.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restoredSession.entries.first?.exercise.name, "Deadlift")

        let secondRestore = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(secondRestore.sets, 0)
        XCTAssertEqual(secondRestore.sessions, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 1, "merge restore must be idempotent")
    }

    func testRestoreRepairsMissingSetRelationshipOnExistingSession() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let entry = SetEntry(exercise: exercise, performedAt: now, weight: 225, reps: 5, restAfterSeconds: 120)
        let session = WorkoutSession(title: "Legs", startedAt: now.addingTimeInterval(-900), endedAt: now, entries: [entry])
        source.insert(exercise)
        source.insert(entry)
        source.insert(session)
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        let destination = makeInMemoryContext()
        let existingExercise = Exercise(id: exercise.id, name: exercise.name, category: exercise.category, metrics: exercise.metrics, defaultRestSeconds: 120)
        let existingSession = WorkoutSession(id: session.id, title: session.title, startedAt: session.startedAt, endedAt: session.endedAt)
        destination.insert(existingExercise)
        destination.insert(existingSession)
        try destination.save()

        let restored = try MarbleBackupService.restore(data: document.data, into: destination)

        XCTAssertEqual(restored.sets, 1)
        XCTAssertEqual(restored.sessions, 0)
        XCTAssertEqual(existingSession.entries.map { $0.id }, [entry.id])
    }

    func testRejectsInvalidBackupBeforeMutation() throws {
        let context = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: Data("not-json".utf8), into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
    }
}
