import SwiftData
import XCTest
@testable import marble

final class WorkoutSessionQueryTests: MarbleTestCase {
    func testQueriesReturnOneActiveAndFiveMostRecentCompletedSessions() throws {
        let context = makeInMemoryContext()
        let active = WorkoutSession(title: "Active", startedAt: now)
        context.insert(active)

        for day in 1...8 {
            let startedAt = MarbleTestCase.stableCalendar.date(byAdding: .day, value: -day, to: now) ?? now
            context.insert(WorkoutSession(
                title: "Completed \(day)",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(3_600)
            ))
        }
        try context.save()

        let activeResults = try context.fetch(WorkoutSessionQueries.active)
        let recentResults = try context.fetch(WorkoutSessionQueries.recentCompleted)

        XCTAssertEqual(activeResults.map(\.id), [active.id])
        XCTAssertEqual(recentResults.count, 5)
        XCTAssertEqual(recentResults.map(\.title), (1...5).map { "Completed \($0)" })
    }
}
