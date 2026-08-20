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
        XCTAssertEqual(entries.first?.importedWorkout?.source, .photoScan)
        XCTAssertEqual(entries.first?.importedWorkout?.setsImported, 3)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.entries.count, 3)
        XCTAssertNotNil(sessions.first?.endedAt)
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
        // The order-preservation cascade keeps every set within a sub-second
        // span of the workout date (see testImportPreservesReviewOrder).
        XCTAssertTrue(entries.allSatisfy { abs($0.performedAt.timeIntervalSince(date)) < 1 })
    }

    /// The journal sorts sets by `performedAt` descending; identical timestamps
    /// come back in undefined order. The importer must space the sets so a
    /// newest-first listing reproduces the exact order of the reviewed draft —
    /// the first exercise typed is the first one shown.
    func testImportPreservesReviewOrder() throws {
        let context = makeInMemoryContext()
        let date = Self.stableCalendar.date(from: DateComponents(year: 2025, month: 6, day: 22, hour: 12))!
        let draft = ParsedWorkoutDraft(performedAt: date, exercises: [
            ParsedExerciseDraft(name: "Bench", sets: [
                ParsedSetDraft(weight: 185, reps: 8),
                ParsedSetDraft(weight: 185, reps: 8)
            ]),
            ParsedExerciseDraft(name: "Row", sets: [
                ParsedSetDraft(weight: 135, reps: 10)
            ]),
            ParsedExerciseDraft(name: "Plank", sets: [
                ParsedSetDraft(durationSeconds: 45),
                ParsedSetDraft(durationSeconds: 45)
            ])
        ])
        _ = try WorkoutScanImporter.import(draft, externalID: "hash-order", in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        ))
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.map(\.exercise.name), ["Bench", "Bench", "Row", "Plank", "Plank"],
                       "Newest-first journal order must match the reviewed draft order")
        // Strictly decreasing: no ties left for the store to scramble.
        for (a, b) in zip(entries, entries.dropFirst()) {
            XCTAssertGreaterThan(a.performedAt, b.performedAt)
        }
        // The whole cascade stays inside the same second and the same day.
        XCTAssertEqual(entries.last?.performedAt, date)
        XCTAssertLessThan(entries.first!.performedAt.timeIntervalSince(date), 1)
        XCTAssertEqual(Self.stableCalendar.startOfDay(for: entries.first!.performedAt),
                       Self.stableCalendar.startOfDay(for: date))
    }

    func testImportAllCommitsIndependentIdentities() throws {
        let context = makeInMemoryContext()
        let first = strengthDraft(name: "Bench")
        let second = strengthDraft(name: "Squat", sets: 2)
        let summary = try WorkoutScanImporter.importAll(
            [(first, "day-1", "Hevy"), (second, "day-2", "Hevy")],
            source: .textEntry,
            in: context
        )
        XCTAssertEqual(summary.importedWorkouts, 2)
        XCTAssertEqual(summary.importedSets, 5)
        XCTAssertEqual(try ledgerCount(in: context), 2)
        let ledgers = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertTrue(ledgers.allSatisfy { $0.originName == "Hevy" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 2)
        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertTrue(entries.allSatisfy { $0.notes == "Imported from Hevy" })
    }

    func testCSVFidelityMapsRPENotesAndSessionClock() throws {
        let context = makeInMemoryContext()
        let start = Self.stableCalendar.date(from: DateComponents(year: 2025, month: 3, day: 28, hour: 17, minute: 29))!
        let draft = ParsedWorkoutDraft(
            performedAt: start,
            endedAt: start.addingTimeInterval(76 * 60),
            durationSeconds: 76 * 60,
            notes: "Felt strong",
            title: "Push Day",
            exercises: [
                ParsedExerciseDraft(name: "Bench", sets: [
                    ParsedSetDraft(weight: 185, reps: 8, difficulty: 9, notes: "paused. Drop set")
                ])
            ]
        )
        _ = try WorkoutScanImporter.import(
            draft,
            externalID: "hevy-1",
            source: .textEntry,
            originName: "Hevy",
            in: context
        )

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertEqual(entry.difficulty, 9)
        XCTAssertEqual(entry.notes, "Imported from Hevy. paused. Drop set")

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.notes, "Imported from Hevy. Felt strong")
        XCTAssertEqual(session.endedAt, start.addingTimeInterval(76 * 60))

        let ledger = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(ledger.durationSeconds, 76 * 60)
    }

    func testImportAllSkipsAlreadyImportedIdentities() throws {
        let context = makeInMemoryContext()
        _ = try WorkoutScanImporter.import(strengthDraft(), externalID: "day-1", source: .textEntry, in: context)
        let summary = try WorkoutScanImporter.importAll(
            [(strengthDraft(), "day-1", nil), (strengthDraft(name: "Row"), "day-2", nil)],
            source: .textEntry,
            in: context
        )
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.importedWorkouts, 1)
        XCTAssertEqual(try ledgerCount(in: context), 2)
    }

    /// Sets with their own explicit date & time keep chronological priority:
    /// the cascade only orders otherwise-identical timestamps.
    func testExplicitPerSetDatesStillOrderChronologically() throws {
        let context = makeInMemoryContext()
        let base = Self.stableCalendar.date(from: DateComponents(year: 2025, month: 6, day: 22, hour: 12))!
        let later = base.addingTimeInterval(3600)
        let draft = ParsedWorkoutDraft(performedAt: base, exercises: [
            ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(weight: 185, reps: 8, performedAt: later)]),
            ParsedExerciseDraft(name: "Row", sets: [ParsedSetDraft(weight: 135, reps: 10)])
        ])
        _ = try WorkoutScanImporter.import(draft, externalID: "hash-explicit", in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        ))
        XCTAssertEqual(entries.map(\.exercise.name), ["Bench", "Row"],
                       "An explicit later set time must still sort above an inherited earlier one")
    }
}
