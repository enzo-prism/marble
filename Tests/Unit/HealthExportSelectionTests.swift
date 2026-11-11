import SwiftData
import XCTest
@testable import marble

@MainActor
final class HealthExportSelectionTests: MarbleTestCase {
    func testRelevantSessionPredicateWorksOnReopenedSQLiteStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("health-export-selection-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Marble.store")
        defer { try? FileManager.default.removeItem(at: folder) }
        let window = now.addingTimeInterval(-14 * 86400)
        try autoreleasepool {
            let container = try PersistenceController.makeRecoveringContainer(at: url)
            let context = ModelContext(container)
            context.insert(WorkoutSession(title: "Old active", startedAt: window.addingTimeInterval(-86400)))
            context.insert(WorkoutSession(title: "Recently finished", startedAt: window.addingTimeInterval(-86400), endedAt: now))
            context.insert(WorkoutSession(title: "Expired", startedAt: window.addingTimeInterval(-2 * 86400), endedAt: window.addingTimeInterval(-86400)))
            try context.save()
        }
        try autoreleasepool {
            let container = try PersistenceController.makeRecoveringContainer(at: url)
            let context = ModelContext(container)
            let sessions = try context.fetch(HealthSessionExporter.relevantSessions(since: window))
            XCTAssertEqual(sessions.map(\.title).sorted(), ["Old active", "Recently finished"])
        }
    }

    func testOvernightAndOldActiveWorkoutsNeverBecomeLegacyDays() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(exercise)
        let yesterday = now.addingTimeInterval(-86400)
        let window = now.addingTimeInterval(-14 * 86400)
        let activeEntries = [yesterday, yesterday.addingTimeInterval(300)].map {
            SetEntry(exercise: exercise, performedAt: $0, reps: 5, restAfterSeconds: 90)
        }
        for (index, entry) in activeEntries.enumerated() {
            context.insert(entry)
            context.insert(WorkoutSession(title: "Unfinished", startedAt: index == 0 ? yesterday : window.addingTimeInterval(-86400), entries: [entry]))
        }
        let unassigned = SetEntry(exercise: exercise, performedAt: yesterday, reps: 8, restAfterSeconds: 60)
        context.insert(unassigned)
        try context.save()

        let sessions = try context.fetch(HealthSessionExporter.relevantSessions(since: window))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy(\.isActive))
        XCTAssertEqual(HealthSessionExporter.unassignedManualEntries(activeEntries + [unassigned], sessions: sessions).map(\.id), [unassigned.id])
    }

    func testWorkoutStartedBeforeWindowAndFinishedRecentlyKeepsItsMembership() throws {
        let context = makeInMemoryContext()
        let window = now.addingTimeInterval(-14 * 86400)
        let recent = WorkoutSession(title: "Long workout", startedAt: window.addingTimeInterval(-86400), endedAt: now)
        let old = WorkoutSession(title: "Old workout", startedAt: window.addingTimeInterval(-2 * 86400), endedAt: window.addingTimeInterval(-86400))
        context.insert(recent)
        context.insert(old)
        try context.save()
        let sessions = try context.fetch(HealthSessionExporter.relevantSessions(since: window))
        XCTAssertEqual(sessions.map(\.id), [recent.id])
        XCTAssertFalse(sessions[0].isActive)
    }
}
