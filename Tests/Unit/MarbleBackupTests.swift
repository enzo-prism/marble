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
        let exercise = Exercise(name: "150m Sprints", category: .run, preferredDistanceUnit: .meters, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 150, durationSeconds: 20, restAfterSeconds: 180)
        let session = WorkoutSession(title: "Pull", startedAt: now.addingTimeInterval(-1200), endedAt: now, entries: [entry])
        let type = SupplementType(name: "Creatine", defaultDose: 5, unit: .g, isFavorite: true)
        let supplement = SupplementEntry(type: type, takenAt: now, dose: 5, unit: .g)
        source.insert(exercise)
        source.insert(entry)
        source.insert(session)
        source.insert(type)
        source.insert(supplement)
        source.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        source.insert(SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 2,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
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
        let restoredSprint = try XCTUnwrap(destination.fetch(FetchDescriptor<SprintPrescription>()).first)
        XCTAssertEqual(restoredSprint.distance, 150)
        XCTAssertEqual(restoredSprint.repetitionCount, 4)
        XCTAssertEqual(restoredSprint.targetLowerSeconds, 19)
        XCTAssertEqual(restoredSprint.targetUpperSeconds, 21)
        let restoredGoal = try XCTUnwrap(destination.fetch(FetchDescriptor<SprintGoalSnapshot>()).first)
        XCTAssertEqual(restoredGoal.setEntryID, entry.id)
        XCTAssertEqual(restoredGoal.repetitionNumber, 2)
        XCTAssertEqual(restoredGoal.plan, SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        let restoredSession = try XCTUnwrap(destination.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restoredSession.entries.first?.exercise.name, "150m Sprints")

        let secondRestore = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(secondRestore.sets, 0)
        XCTAssertEqual(secondRestore.sessions, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 1, "merge restore must be idempotent")
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 1)
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

    func testLegacyBackupWithoutSprintPrescriptionsStillRestores() throws {
        let source = makeInMemoryContext()
        source.insert(Exercise(name: "Legacy Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "sprintPrescriptions")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.exercises, 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
    }

    func testLegacyBackupWithoutSprintGoalSnapshotsStillRestores() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Legacy Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        source.insert(exercise)
        source.insert(SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "sprintGoalSnapshots")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }

    func testRestoreRejectsInvalidSprintPrescriptionBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        source.insert(exercise)
        source.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["sprintPrescriptions"] as? [[String: Any]])
        records[0]["distance"] = 0
        json["sprintPrescriptions"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
    }

    func testRestoreRejectsSprintGoalSnapshotReferencingMissingSetBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        )
        source.insert(exercise)
        source.insert(entry)
        source.insert(SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 1,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["sprintGoalSnapshots"] as? [[String: Any]])
        records[0]["setEntryID"] = UUID().uuidString
        json["sprintGoalSnapshots"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }
}
