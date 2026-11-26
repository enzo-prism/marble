import AppIntents
import Foundation
import SwiftData
import XCTest
@testable import marble

@MainActor
final class WorkoutCommandTests: MarbleTestCase {
    override func tearDown() {
        AppIntentsSupport.container = nil
        RestActivityController.shared.cancelRest()
        super.tearDown()
    }
    private func context() -> ModelContext {
        let container = makeInMemoryContainer()
        AppIntentsSupport.register(container: container)
        return container.mainContext
    }
    private func exercise(in context: ModelContext) -> Exercise {
        let value = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 90, createdAt: now)
        context.insert(value)
        return value
    }

    func testExplicitSprintTimePreservesTenthsAndSessionMembership() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let session = WorkoutSession(title: "Track", startedAt: now)
        context.insert(session)
        try context.save()
        let outcome = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name, distance: 50, distanceUnit: .meters, durationSeconds: 7.4))
        let entry = try XCTUnwrap(outcome.entry)
        let details = try context.fetch(FetchDescriptor<SprintRepDetail>())
        XCTAssertEqual(details.first?.durationTenths, 74)
        XCTAssertEqual(entry.durationSeconds, 7)
        XCTAssertEqual(session.entries.map(\.id), [entry.id])
        XCTAssertTrue(outcome.message.contains("7.4s"))
        XCTAssertTrue(LoggedSetEntity(entry).summary.contains("7.4s"))
    }

    func testTimedPerformanceIsNeverInventedFromHistory() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let original = SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(-60), distance: 50, durationSeconds: 8, restAfterSeconds: 90)
        context.insert(original)
        try context.save()
        let outcome = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name))
        XCTAssertNil(outcome.entry)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)
    }

    func testRepeatAttachesSessionAndCopiesPreciseSprintMetadata() throws {
        let context = context()
        let exercise = exercise(in: context)
        let original = SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(-60), distance: 50, durationSeconds: 7, restAfterSeconds: 90)
        let session = WorkoutSession(title: "Track", startedAt: now.addingTimeInterval(-120), entries: [original])
        context.insert(original); context.insert(session)
        context.insert(SprintRepDetail(setEntryID: original.id, durationTenths: 74, targetLowerTenths: 70, targetUpperTenths: 80, createdAt: now))
        try context.save()
        let repeated = try XCTUnwrap(WorkoutCommands.repeatSet(original, into: session, in: context))
        XCTAssertEqual(session.entries.count, 2)
        XCTAssertTrue(session.entries.contains { $0.id == repeated.id })
        let id = repeated.id
        let detail = try context.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == id })).first
        XCTAssertEqual(detail?.durationTenths, 74)
        XCTAssertEqual(detail?.targetLowerTenths, 70)
    }

    func testRepeatSourcePrefersActiveSessionOverGlobalHistory() throws {
        let context = context()
        let exercise = exercise(in: context)
        let current = SetEntry(exercise: exercise, performedAt: now.addingTimeInterval(-60), restAfterSeconds: 0)
        let unrelated = SetEntry(exercise: exercise, performedAt: now, restAfterSeconds: 0)
        context.insert(current); context.insert(unrelated)
        context.insert(WorkoutSession(title: "Track", startedAt: now.addingTimeInterval(-120), entries: [current]))
        try context.save()
        XCTAssertEqual(try WorkoutCommands.latestRepeatSource(in: context)?.id, current.id)
    }

    func testInvalidNumbersDoNotWrite() async throws {
        let context = context()
        let exercise = exercise(in: context)
        try context.save()
        for duration in [Double.nan, .infinity, -1, 0] {
            let result = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name, distance: 50, durationSeconds: duration))
            XCTAssertNil(result.entry)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
    }

    func testCorrectionTargetsConfirmedSetAndKeepsPreciseTime() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let first = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name,
            distance: 50, durationSeconds: 7.4))
        let original = try XCTUnwrap(first.entry)
        let second = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name,
            distance: 50, durationSeconds: 8.2))
        var intent = CorrectLoggedSetIntent()
        intent.set = LoggedSetEntity(original)
        intent.durationSeconds = 7.1
        _ = try await intent.perform()
        XCTAssertEqual(LoggedSetEntity(original).durationSeconds, 7.1)
        XCTAssertEqual(LoggedSetEntity(try XCTUnwrap(second.entry)).durationSeconds, 8.2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 2)
    }

    func testInvalidCorrectionLeavesConfirmedSetUnchanged() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let logged = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name,
            distance: 50, durationSeconds: 7.4))
        let original = try XCTUnwrap(logged.entry)
        var intent = CorrectLoggedSetIntent()
        intent.set = LoggedSetEntity(original)
        intent.durationSeconds = .nan
        do { _ = try await intent.perform(); XCTFail("Invalid correction should fail") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertEqual(LoggedSetEntity(original).durationSeconds, 7.4)
    }

    func testWatchRetryDoesNotDuplicateConfirmedSet() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let session = try XCTUnwrap(WorkoutCommands.start(in: context))
        let logged = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name,
            distance: 50, durationSeconds: 7.4))
        let source = try XCTUnwrap(logged.entry)
        let request = WatchWorkoutRequest(id: UUID(), action: .repeatSet, sessionID: session.id,
            setID: source.id, createdAt: AppEnvironment.now)
        let first = await WatchWorkoutCoordinator.shared.handle(request)
        let retry = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(first.succeeded)
        XCTAssertTrue(retry.succeeded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 2)
        XCTAssertEqual(session.entries.count, 2)
        let repeated = try XCTUnwrap(session.entries.first { $0.id == request.id })
        XCTAssertEqual(LoggedSetEntity(repeated).durationSeconds, 7.4)
    }

    func testWatchCannotRepeatAnOutdatedSession() async throws {
        let context = context()
        let session = try XCTUnwrap(WorkoutCommands.start(in: context))
        let request = WatchWorkoutRequest(id: UUID(), action: .repeatSet, sessionID: UUID(),
            setID: UUID(), createdAt: AppEnvironment.now)
        let response = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertFalse(response.succeeded)
        XCTAssertTrue(session.entries.isEmpty)
    }

    func testWatchFinishRetrySucceedsForAlreadySavedSession() async throws {
        let context = context()
        let session = try XCTUnwrap(WorkoutCommands.start(in: context))
        let request = WatchWorkoutRequest(id: UUID(), action: .finish, sessionID: session.id,
            setID: nil, createdAt: AppEnvironment.now)
        let first = await WatchWorkoutCoordinator.shared.handle(request)
        let retry = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(first.succeeded)
        XCTAssertTrue(retry.succeeded)
        XCTAssertNotNil(session.endedAt)
        XCTAssertNil(WorkoutSessionIntentSupport.activeSession(in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)

        TestHooks.overrideNow = now.addingTimeInterval(180)
        let expiredRetry = WatchWorkoutRequest(id: request.id, action: .finish, sessionID: session.id,
            setID: nil, createdAt: request.createdAt)
        let late = await WatchWorkoutCoordinator.shared.handle(expiredRetry)
        XCTAssertTrue(late.succeeded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testWatchFinishRetryDoesNotStopANewerWorkout() async throws {
        let context = context()
        let first = try XCTUnwrap(WorkoutCommands.start(in: context))
        let request = WatchWorkoutRequest(id: UUID(), action: .finish, sessionID: first.id,
            setID: nil, createdAt: AppEnvironment.now)
        let finished = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(finished.succeeded)
        let newer = try XCTUnwrap(WorkoutCommands.start(in: context))
        XCTAssertTrue(newer.isActive)
        let retry = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(retry.succeeded)
        XCTAssertTrue(newer.isActive)
        XCTAssertNotNil(first.endedAt)
        XCTAssertNil(newer.endedAt)
        XCTAssertEqual(WorkoutSessionIntentSupport.activeSession(in: context)?.id, newer.id)
        XCTAssertFalse(NativeWorkoutController.tracks(first.id, liveSessionID: newer.id.uuidString))
        XCTAssertTrue(NativeWorkoutController.tracks(newer.id, liveSessionID: newer.id.uuidString))
    }

    func testWatchStartRetrySucceedsForAlreadySavedSessionAfterExpiry() async throws {
        let context = context()
        let request = WatchWorkoutRequest(id: UUID(), action: .start, sessionID: nil,
            setID: nil, createdAt: AppEnvironment.now)
        let first = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)

        TestHooks.overrideNow = now.addingTimeInterval(180)
        let late = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertTrue(late.succeeded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testWatchFinishOfUnknownSessionIsNotRetryable() async throws {
        let context = context()
        _ = try XCTUnwrap(WorkoutCommands.start(in: context))
        let request = WatchWorkoutRequest(id: UUID(), action: .finish, sessionID: UUID(),
            setID: nil, createdAt: AppEnvironment.now)
        let response = await WatchWorkoutCoordinator.shared.handle(request)
        XCTAssertFalse(response.succeeded)
        XCTAssertFalse(response.retryable ?? false)
        XCTAssertTrue(response.shouldClearPendingRequest)
    }

    func testSessionQueryReturnsJustFinishedWorkout() async throws {
        let context = context()
        let session = try XCTUnwrap(WorkoutCommands.start(in: context))
        XCTAssertTrue(WorkoutCommands.finish(session, in: context))
        let results = try await WorkoutSessionEntityQuery().suggestedEntities()
        XCTAssertEqual(results.map(\.id), [session.id])
    }

    func testDeviceRepairRequiresExactDateAndAnEmptySession() throws {
        let context = context()
        let exercise = exercise(in: context)
        let populated = WorkoutSession(title: "Preserve", startedAt: now, createdAt: now)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 50, durationSeconds: 7, restAfterSeconds: 0)
        context.insert(entry); context.insert(populated); populated.append(entry)
        let empty = WorkoutSession(title: "Empty", startedAt: now, createdAt: now)
        context.insert(empty); try context.save()
        XCTAssertFalse(try DebugDeviceRepair.removeEmptySession(id: populated.id, expectedCreatedAt: now, in: context))
        XCTAssertFalse(try DebugDeviceRepair.removeEmptySession(id: empty.id, expectedCreatedAt: now.addingTimeInterval(1), in: context))
        XCTAssertTrue(try DebugDeviceRepair.removeEmptySession(id: empty.id, expectedCreatedAt: now, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 1)
    }

    func testBackdatedLogDoesNotJoinTodaysWorkout() async throws {
        let context = context()
        let exercise = exercise(in: context)
        let session = WorkoutSession(title: "Today", startedAt: now)
        context.insert(session); try context.save()
        let outcome = try await WorkoutCommands.log(.init(exerciseID: exercise.id, exerciseName: exercise.name, distance: 50, durationSeconds: 7.4, performedAt: now.addingTimeInterval(-86400)))
        XCTAssertNotNil(outcome.entry)
        XCTAssertTrue(session.entries.isEmpty)
    }
}

@MainActor
final class HealthExportTransactionTests: XCTestCase {
    func testEffortRetryNeverCreatesAnotherWorkout() async {
        let name = "marble.export.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let transaction = HealthExportTransaction(defaults: defaults)
        var creates = 0
        var attachments = 0
        enum Failure: Error { case attachment }
        let first = await transaction.run(identifier: "session", lookup: { Optional<Int>.none }, create: { creates += 1; return 1 }, attachEffort: { _ in attachments += 1; throw Failure.attachment })
        XCTAssertFalse(first)
        XCTAssertTrue(transaction.checkpoint(for: "session").workoutSaved)
        // Construct a new coordinator to prove the checkpoint survives process-local state.
        let second = await HealthExportTransaction(defaults: defaults).run(identifier: "session", lookup: { 1 }, create: { creates += 1; return 2 }, attachEffort: { _ in attachments += 1 })
        XCTAssertTrue(second)
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(attachments, 2)
    }

    func testSuccessfulLockedSaveIsNotRecreatedWhenUnreadable() async {
        let name = "marble.export.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let transaction = HealthExportTransaction(defaults: defaults)
        var creates = 0
        for _ in 0..<2 {
            let complete = await transaction.run(identifier: "locked", lookup: { Optional<Int>.none }, create: { creates += 1; return Optional<Int>.none }, attachEffort: { _ in XCTFail("No readable workout") })
            XCTAssertFalse(complete)
        }
        XCTAssertEqual(creates, 1)
    }
}
