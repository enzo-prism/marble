import SwiftData
import XCTest
@testable import marble

@MainActor
final class SetLoggingTests: MarbleTestCase {
    func testRepeatLatestCopiesWeightAndAttachesSession() {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "Bench",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        context.insert(exercise)
        let original = SetEntry(
            exercise: exercise,
            performedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weight: 185,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 90
        )
        context.insert(original)
        let session = WorkoutSession(title: "Today", startedAt: Date(timeIntervalSince1970: 1_700_010_000))
        context.insert(session)
        XCTAssertTrue(context.saveOrRollback())

        let duplicate = SetLogging.repeatLatest(of: original, into: session, in: context)

        XCTAssertNotNil(duplicate)
        XCTAssertNotEqual(duplicate?.id, original.id)
        XCTAssertEqual(duplicate?.weight, 185)
        XCTAssertEqual(duplicate?.reps, 5)
        XCTAssertTrue(session.entries.contains(where: { $0.id == duplicate?.id }))
    }
}
