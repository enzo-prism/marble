import SwiftData
import XCTest
@testable import marble

@MainActor
final class TrainingConsistencyQueryTests: MarbleTestCase {
    func testOverviewCountsOnDiskHistory() throws {
        try measureBaseline(setCount: 600)
    }

    func testOverviewBaselineWithFiveThousandSets() throws {
        try requireBenchmarkOptIn()
        try measureBaseline(setCount: 5_000)
    }

    func testOverviewBaselineWithTwentyThousandSets() throws {
        try requireBenchmarkOptIn()
        try measureBaseline(setCount: 20_000)
    }

    private func requireBenchmarkOptIn() throws {
        guard ProcessInfo.processInfo.environment["MARBLE_RUN_STORE_PERFORMANCE"] == "1" else {
            throw XCTSkip("Opt-in on-disk benchmark: set MARBLE_RUN_STORE_PERFORMANCE=1")
        }
    }

    private func measureBaseline(setCount: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConsistencyQueryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: MarbleSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        writer.insert(exercise)
        for index in 0..<setCount {
            let date = now.addingTimeInterval(Double(-(index % 365)) * 86_400)
            writer.insert(SetEntry(exercise: exercise, performedAt: date, weight: 100, reps: 5, restAfterSeconds: 90))
        }
        try writer.save()

        let fullContext = ModelContext(container)
        let fullStart = ContinuousClock.now
        let full = try fullContext.fetch(FetchDescriptor<SetEntry>())
        let actual = TrainingConsistency.snapshot(history: full, target: 3, now: now, calendar: Self.stableCalendar)
        let fullDuration = fullStart.duration(to: .now)

        XCTAssertEqual(actual.lifetimeSets, setCount)
        XCTAssertEqual(actual.lifetimeActiveDays, min(setCount, 365))
        let evidence = "SQLite Progress overview baseline, \(setCount) sets: existing full fetch + consistency calculation \(fullDuration). Correct set/day counts; warm store. No optimization comparison or physical-device claim."
        let attachment = XCTAttachment(string: evidence)
        attachment.lifetime = .keepAlways
        add(attachment)
        print(evidence)
    }
}
