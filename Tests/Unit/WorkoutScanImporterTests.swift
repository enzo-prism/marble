import SwiftData
import XCTest
@testable import marble

/// Verifies that a reviewed scan draft commits to the journal correctly: persistence,
/// exercise resolution/reuse, per-exercise metrics, image-hash dedup, and dates.
@MainActor
final class WorkoutScanImporterTests: MarbleTestCase {

    private func strengthDraft(name: String = "Bench", sets: Int = 3, reps: Int = 5, weight: Double? = 135) -> ParsedWorkoutDraft {
        let setDrafts = (0..<sets).map { _ in
            ParsedSetDraft(weight: weight, weightUnit: .lb, reps: reps)
        }
        return ParsedWorkoutDraft(exercises: [ParsedExerciseDraft(name: name, sets: setDrafts)])
    }

    private func setEntryCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<SetEntry>()).count
    }

    private func exerciseCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Exercise>()).count
    }

    private func ledgerCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<ImportedWorkout>()).count
    }

    func testImportPersistsSetsAndLedger() throws {
        let context = makeInMemoryContext()
        let summary = try WorkoutScanImporter.import(strengthDraft(), externalID: "hash-1", in: context)

        XCTAssertEqual(summary.importedWorkouts, 1)
        XCTAssertEqual(summary.importedSets, 3)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(try setEntryCount(in: context), 3)
        XCTAssertEqual(try ledgerCount(in: context), 1)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.exercise.name == "Bench" && $0.reps == 5 && $0.weight == 135 })
        XCTAssertEqual(entries.first?.notes, WorkoutScanImporter.importNote)
    }

    func testDedupSkipsIdenticalImage() throws {
        let context = makeInMemoryContext()
        _ = try WorkoutScanImporter.import(strengthDraft(), externalID: "hash-1", in: context)
        let second = try WorkoutScanImporter.import(strengthDraft(), externalID: "hash-1", in: context)

        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(second.importedWorkouts, 0)
        XCTAssertEqual(try setEntryCount(in: context), 3) // unchanged
        XCTAssertEqual(try ledgerCount(in: context), 1)
    }

    func testDifferentImageImportsAgain() throws {
        let context = makeInMemoryContext()
        _ = try WorkoutScanImporter.import(strengthDraft(), externalID: "hash-1", in: context)
        let second = try WorkoutScanImporter.import(strengthDraft(), externalID: "hash-2", in: context)

        XCTAssertEqual(second.importedWorkouts, 1)
        XCTAssertEqual(try setEntryCount(in: context), 6)
        XCTAssertEqual(try ledgerCount(in: context), 2)
    }

    func testResolvesExistingExerciseCaseInsensitively() throws {
        let context = makeInMemoryContext()
        let existing = Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(existing)
        try context.save()

        _ = try WorkoutScanImporter.import(strengthDraft(name: "bench press"), externalID: "hash-1", in: context)

        XCTAssertEqual(try exerciseCount(in: context), 1, "Existing exercise should be reused, not duplicated")
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.exercise.id == existing.id })
    }

    func testCreatesExerciseWithBodyweightMetrics() throws {
        let context = makeInMemoryContext()
        let draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(name: "Pull Ups", sets: [
                ParsedSetDraft(reps: 12), ParsedSetDraft(reps: 10), ParsedSetDraft(reps: 8)
            ])
        ])
        _ = try WorkoutScanImporter.import(draft, externalID: "hash-bw", in: context)

        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertTrue(exercise.metrics.usesReps)
        XCTAssertFalse(exercise.metrics.usesWeight)
        XCTAssertFalse(exercise.metrics.usesDistance)
        XCTAssertFalse(exercise.metrics.usesDuration)
    }

    func testCardioSetValuesAndMetrics() throws {
        let context = makeInMemoryContext()
        let draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(name: "Run", sets: [
                ParsedSetDraft(distance: 5, distanceUnit: .kilometers, durationSeconds: 1500)
            ])
        ])
        _ = try WorkoutScanImporter.import(draft, externalID: "hash-run", in: context)

        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertTrue(exercise.metrics.usesDistance)
        XCTAssertTrue(exercise.metrics.usesDuration)
        XCTAssertFalse(exercise.metrics.usesWeight)

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertEqual(entry.distance, 5)
        XCTAssertEqual(entry.durationSeconds, 1500)
    }

    func testEmptyDraftImportsNothing() throws {
        let context = makeInMemoryContext()
        let empty = ParsedWorkoutDraft(exercises: [ParsedExerciseDraft(name: "Squat", sets: [])])
        let summary = try WorkoutScanImporter.import(empty, externalID: "hash-empty", in: context)

        XCTAssertEqual(summary.importedWorkouts, 0)
        XCTAssertEqual(summary.importedSets, 0)
        XCTAssertEqual(try setEntryCount(in: context), 0)
        XCTAssertEqual(try ledgerCount(in: context), 0)
    }

    func testPerformedAtUsesDraftDateWhenPresent() throws {
        let context = makeInMemoryContext()
        let date = Self.stableCalendar.date(from: DateComponents(year: 2025, month: 6, day: 22, hour: 12))!
        var draft = strengthDraft()
        draft.performedAt = date
        _ = try WorkoutScanImporter.import(draft, externalID: "hash-dated", in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.performedAt == date })
    }
}
