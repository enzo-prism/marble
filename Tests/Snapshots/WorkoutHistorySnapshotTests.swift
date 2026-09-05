import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class WorkoutHistorySnapshotTests: SnapshotTestCase {
    func testHistoryEmpty() {
        let container = SnapshotFixtures.makeContainer()
        assertSnapshot(NavigationStack { WorkoutHistoryView(snapshotSessions: []) }.modelContainer(container), named: "History_Empty")
    }

    func testHistoryPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let session = makeSession(in: container)
        assertSnapshot(NavigationStack { WorkoutHistoryView(snapshotSessions: [session]) }.modelContainer(container), named: "History_Populated")
    }

    func testSessionDetailPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let session = makeSession(in: container)
        assertSnapshot(NavigationStack { WorkoutSessionDetailView(snapshotSession: session) }.modelContainer(container), named: "History_Detail")
    }

    func testSessionDetailEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let session = WorkoutSession(title: "Recovery", startedAt: SnapshotFixtures.now, endedAt: SnapshotFixtures.now)
        container.mainContext.insert(session)
        try? container.mainContext.save()
        assertSnapshot(NavigationStack { WorkoutSessionDetailView(snapshotSession: session) }.modelContainer(container), named: "History_DetailEmpty")
    }

    private func makeSession(in container: ModelContainer) -> WorkoutSession {
        let context = container.mainContext
        SnapshotFixtures.seedBase(in: context)
        let exercise = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let entries = (0..<3).map { index in
            SetEntry(exercise: exercise, performedAt: SnapshotFixtures.now.addingTimeInterval(Double(index)), weight: 185, reps: 8, difficulty: 7, restAfterSeconds: 90)
        }
        entries.forEach { context.insert($0) }
        let session = WorkoutSession(title: "Upper Body Strength", startedAt: SnapshotFixtures.now, endedAt: SnapshotFixtures.now.addingTimeInterval(2700), notes: "Steady reps. Leave room to build next week.", entries: entries)
        context.insert(session)
        try? context.save()
        return session
    }
}
