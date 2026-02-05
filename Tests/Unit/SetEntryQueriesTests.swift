import SwiftData
import XCTest
@testable import marble

final class SetEntryQueriesTests: MarbleTestCase {
    func testMostRecentEntryReturnsNilWhenEmpty() {
        let context = makeInMemoryContext()

        let exercise = Exercise(
            name: "Bench",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        context.insert(exercise)

        let result = SetEntryQueries.mostRecentEntry(for: exercise.id, in: context)
        XCTAssertNil(result)
    }

    func testMostRecentEntryReturnsLatest() {
        let context = makeInMemoryContext()

        let exercise = Exercise(
            name: "Bench",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        context.insert(exercise)

        let first = SetEntry(
            exercise: exercise,
            performedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weight: 135,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 7,
            restAfterSeconds: 90
        )
        let second = SetEntry(
            exercise: exercise,
            performedAt: Date(timeIntervalSince1970: 1_700_010_000),
            weight: 145,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 90
        )
        context.insert(first)
        context.insert(second)

        let result = SetEntryQueries.mostRecentEntry(for: exercise.id, in: context)
        XCTAssertEqual(result?.id, second.id)
    }
}
