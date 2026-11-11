import SwiftData
import SwiftUI
import XCTest
@testable import marble

@MainActor
final class WorkoutHistorySnapshotTests: SnapshotTestCase {
    func testHistoryEmpty() {
        let container = SnapshotFixtures.makeContainer()
        assertHistorySnapshot(named: "History_Empty", expectedText: ["No completed sessions"]) {
            NavigationStack { WorkoutHistoryView(snapshotSessions: []) }.modelContainer(container)
        }
    }

    func testHistoryPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let session = makeSession(in: container)
        // XXXL wraps the title so OCR sees "Upper Body Streng" then "3 sets"
        // then "th". Require a prefix that stays contiguous, not "Bench Press"
        // (the list row never draws the exercise name).
        assertHistorySnapshot(named: "History_Populated", expectedText: ["Upper Body"]) {
            NavigationStack { WorkoutHistoryView(snapshotSessions: [session]) }.modelContainer(container)
        }
    }

    func testSessionDetailPopulated() {
        let container = SnapshotFixtures.makeContainer()
        let session = makeSession(in: container)
        // XXXL parks set rows below the fold, so "Bench Press" is not in the
        // first frame. The notes line is.
        assertHistorySnapshot(named: "History_Detail", expectedText: ["Steady reps"]) {
            NavigationStack { WorkoutSessionDetailView(snapshotSession: session) }.modelContainer(container)
        }
    }

    func testSessionDetailEmpty() {
        let container = SnapshotFixtures.makeContainer()
        let session = WorkoutSession(title: "Recovery", startedAt: SnapshotFixtures.now, endedAt: SnapshotFixtures.now)
        container.mainContext.insert(session)
        try? container.mainContext.save()
        assertHistorySnapshot(named: "History_DetailEmpty", expectedText: ["Recovery"]) {
            NavigationStack { WorkoutSessionDetailView(snapshotSession: session) }.modelContainer(container)
        }
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
