import SwiftData
import XCTest
@testable import marble

/// Opt-in SQLite benchmarks. Run with MARBLE_RUN_STORE_PERFORMANCE=1; these
/// report observed times, never enforce a machine-dependent latency threshold.
@MainActor
final class WorkoutHistoryStorePerformanceTests: MarbleTestCase {
    func testHistoryWithFiveThousandSets() throws { try compareHistoryQueries(setCount: 5_000) }
    func testHistoryWithTwentyThousandSets() throws { try compareHistoryQueries(setCount: 20_000) }

    private func compareHistoryQueries(setCount: Int) throws {
        guard ProcessInfo.processInfo.environment["MARBLE_RUN_STORE_PERFORMANCE"] == "1" else {
            throw XCTSkip("Opt-in on-disk benchmark: set MARBLE_RUN_STORE_PERFORMANCE=1")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryBenchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: MarbleSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let exercise = Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        writer.insert(exercise)
        for sessionIndex in 0..<(setCount / 20) {
            let date = now.addingTimeInterval(Double(-sessionIndex) * 86_400)
            let session = WorkoutSession(title: "Strength", startedAt: date, endedAt: date.addingTimeInterval(3600))
            writer.insert(session)
            for index in 0..<20 {
                let entry = SetEntry(exercise: exercise, performedAt: date.addingTimeInterval(Double(index)), weight: 100, reps: 8, restAfterSeconds: 90)
                writer.insert(entry)
                session.entries.append(entry)
            }
        }
        try writer.save()

        // Separate contexts prevent reuse of the first fetch's registered models.
        // This is a warm SQLite comparison, not a cold launch/device claim.
        let fullContext = ModelContext(container)
        let fullStart = ContinuousClock.now
        let full = try fullContext.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let expected = Array(full.filter { session in
            session.title.localizedStandardContains("Bench") ||
            session.entries.contains { $0.exercise.name.localizedStandardContains("Bench") }
        }.prefix(WorkoutHistoryQuery.pageSize).map(\.id))
        let fullDuration = fullStart.duration(to: .now)

        let pageContext = ModelContext(container)
        let pageStart = ContinuousClock.now
        let page = try pageContext.fetch(WorkoutHistoryQuery.descriptor(search: "Bench", day: nil))
        let actual = Array(page.prefix(WorkoutHistoryQuery.pageSize).map(\.id))
        let pageDuration = pageStart.duration(to: .now)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(page.count, WorkoutHistoryQuery.pageSize + 1)
        let evidence = "SQLite history, \(setCount) sets: full fetch + filter \(fullDuration); bounded database search \(pageDuration). Equal first-page IDs. Warm store, separate contexts."
        let attachment = XCTAttachment(string: evidence)
        attachment.lifetime = .keepAlways
        add(attachment)
        print(evidence)
    }
}
