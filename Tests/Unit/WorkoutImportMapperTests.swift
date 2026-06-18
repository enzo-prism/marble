import SwiftData
import XCTest
@testable import marble

final class WorkoutImportMapperTests: MarbleTestCase {
    private func cardioRecord(kind: ImportedActivityKind = .running, meters: Double = 5000, seconds: Int = 1800) -> WorkoutImportRecord {
        WorkoutImportRecord(
            source: .appleHealth,
            externalID: "hk-1",
            date: now,
            title: kind.displayName,
            kind: kind,
            distanceMeters: meters,
            durationSeconds: seconds,
            calories: 320
        )
    }

    private func strengthRecord(sets: [ImportedStrengthSet]) -> WorkoutImportRecord {
        WorkoutImportRecord(
            source: .garminConnect,
            externalID: "gc-1",
            date: now,
            title: "Strength",
            kind: .strength,
            strengthSets: sets
        )
    }

    func testCardioMapsToSingleSetEntryWithDistanceAndDuration() throws {
        let context = makeInMemoryContext()
        let record = cardioRecord()

        let entries = try WorkoutImportMapper.makeSetEntries(for: record, in: context)

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.distance, 5000)
        XCTAssertEqual(entry.distanceUnit, .meters)
        XCTAssertEqual(entry.durationSeconds, 1800)
        XCTAssertEqual(entry.exercise.category, .run)
        XCTAssertEqual(entry.exercise.name, "Running")
    }

    func testStrengthWithSetsCreatesOneEntryPerSet() throws {
        let context = makeInMemoryContext()
        let record = strengthRecord(sets: [
            ImportedStrengthSet(exerciseName: "Bench Press", weightKilograms: 80, reps: 8, restSeconds: 90),
            ImportedStrengthSet(exerciseName: "Barbell Squat", weightKilograms: 100, reps: 5, restSeconds: 120)
        ])

        let entries = try WorkoutImportMapper.makeSetEntries(for: record, in: context)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].weight, 80)
        XCTAssertEqual(entries[0].weightUnit, .kg)
        XCTAssertEqual(entries[0].reps, 8)
        XCTAssertEqual(entries[0].exercise.name, "Bench Press")
        XCTAssertEqual(entries[0].exercise.category, .chest)
        XCTAssertEqual(entries[1].weight, 100)
        XCTAssertEqual(entries[1].reps, 5)
        XCTAssertEqual(entries[1].exercise.category, .quads)
    }

    func testStrengthWithoutSetsFallsBackToDurationEntry() throws {
        let context = makeInMemoryContext()
        let record = WorkoutImportRecord(
            source: .appleHealth,
            externalID: "hk-2",
            date: now,
            title: "Strength",
            kind: .strength,
            durationSeconds: 2700
        )

        let entries = try WorkoutImportMapper.makeSetEntries(for: record, in: context)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.durationSeconds, 2700)
        XCTAssertEqual(entries.first?.exercise.name, "Strength Training")
    }

    func testImportingSameRecordTwiceIsDeduplicated() throws {
        let context = makeInMemoryContext()
        let record = cardioRecord()

        let first = try WorkoutImporter.importWorkout(record, in: context)
        let second = try WorkoutImporter.importWorkout(record, in: context)

        XCTAssertEqual(first, .imported(setCount: 1))
        XCTAssertEqual(second, .alreadyImported)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 1)
    }

    func testExerciseResolutionReusesExistingByNameCaseInsensitive() throws {
        let context = makeInMemoryContext()
        let existing = Exercise(name: "RUNNING", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        context.insert(existing)

        let beforeCount = try context.fetch(FetchDescriptor<Exercise>()).count
        _ = try WorkoutImportMapper.makeSetEntries(for: cardioRecord(), in: context)
        let afterCount = try context.fetch(FetchDescriptor<Exercise>()).count

        XCTAssertEqual(afterCount, beforeCount)
    }

    func testImportRecordsSummaryCountsImportedAndSkipped() throws {
        let context = makeInMemoryContext()
        let records = [
            cardioRecord(),
            WorkoutImportRecord(source: .appleHealth, externalID: "hk-1", date: now, title: "Running", kind: .running, distanceMeters: 1000, durationSeconds: 360),
            WorkoutImportRecord(source: .garminConnect, externalID: "gc-cyc", date: now, title: "Cycling", kind: .cycling, distanceMeters: 20000, durationSeconds: 3600)
        ]

        let summary = try WorkoutImporter.importRecords(records, in: context)

        XCTAssertEqual(summary.importedWorkouts, 2)
        XCTAssertEqual(summary.importedSets, 2)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testInferredCategoryHeuristics() {
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Bench Press"), .chest)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Barbell Squat"), .quads)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Romanian Deadlift"), .hamstrings)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Cable Row"), .back)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Dumbbell Curl"), .biceps)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Triceps Pushdown"), .triceps)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Overhead Press"), .shoulders)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Hanging Leg Raise"), .core)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Mystery Move"), .other)
    }

    func testCyclingMapsToRunCategoryCardioExercise() throws {
        let context = makeInMemoryContext()
        let record = cardioRecord(kind: .cycling, meters: 25000, seconds: 3600)

        let entries = try WorkoutImportMapper.makeSetEntries(for: record, in: context)

        XCTAssertEqual(entries.first?.exercise.name, "Cycling")
        XCTAssertEqual(entries.first?.exercise.category, .run)
    }

    func testInferredCategoryDistinguishesLegCurlFromOtherLegWork() {
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Seated Leg Curl"), .hamstrings)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Leg Press"), .quads)
        XCTAssertEqual(WorkoutImportMapper.inferredCategory(for: "Leg Extension"), .quads)
    }

    func testDeduplicationKeyIsStableAndSourceScoped() {
        XCTAssertEqual(ImportedWorkout.deduplicationKey(source: .garminConnect, externalID: "42"), "garminConnect:42")
        XCTAssertNotEqual(
            ImportedWorkout.deduplicationKey(source: .appleHealth, externalID: "42"),
            ImportedWorkout.deduplicationKey(source: .garminConnect, externalID: "42")
        )
    }
}
