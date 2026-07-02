import SwiftData
import XCTest
@testable import marble

private enum MockSaveError: Error {
    case failed
}

final class WorkoutImporterTests: MarbleTestCase {
    private func cardioRecord(source: ImportSource = .appleHealth, externalID: String = "hk-1") -> WorkoutImportRecord {
        WorkoutImportRecord(
            source: source,
            externalID: externalID,
            date: now,
            title: "Running",
            kind: .running,
            distanceMeters: 5000,
            durationSeconds: 1800
        )
    }

    func testAlreadyImportedReflectsSourceAndExternalID() throws {
        let context = makeInMemoryContext()
        let apple = cardioRecord(source: .appleHealth, externalID: "shared")
        let garmin = cardioRecord(source: .garminConnect, externalID: "shared")

        XCTAssertFalse(try WorkoutImporter.alreadyImported(apple, in: context))
        _ = try WorkoutImporter.importWorkout(apple, in: context)

        XCTAssertTrue(try WorkoutImporter.alreadyImported(apple, in: context))
        // Same externalID from a different source is a distinct workout.
        XCTAssertFalse(try WorkoutImporter.alreadyImported(garmin, in: context))
    }

    func testImportWorkoutWritesLedgerRowWithSetsImportedCount() throws {
        let context = makeInMemoryContext()
        _ = try WorkoutImporter.importWorkout(cardioRecord(), in: context)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.source, .appleHealth)
        XCTAssertEqual(log.externalID, "hk-1")
        XCTAssertEqual(log.title, "Running")
        XCTAssertEqual(log.setsImported, 1)
    }

    func testImportRecordsIsIdempotentAcrossBatches() throws {
        let context = makeInMemoryContext()
        let record = cardioRecord()

        let first = try WorkoutImporter.importRecords([record], in: context)
        let second = try WorkoutImporter.importRecords([record], in: context)

        XCTAssertEqual(first.importedWorkouts, 1)
        XCTAssertEqual(first.skipped, 0)
        XCTAssertEqual(second.importedWorkouts, 0)
        XCTAssertEqual(second.skipped, 1)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 1)
    }

    func testImportRecordsSkipsDuplicateRecordsInsideSingleBatch() throws {
        let context = makeInMemoryContext()
        let record = cardioRecord()

        let summary = try WorkoutImporter.importRecords([record, record], in: context)

        XCTAssertEqual(summary.importedWorkouts, 1)
        XCTAssertEqual(summary.importedSets, 1)
        XCTAssertEqual(summary.skipped, 1)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 1)
        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(sets.count, 1)
    }

    func testImportRecordsKeepsSameExternalIDFromDifferentSourcesDistinctWithinBatch() throws {
        let context = makeInMemoryContext()
        let apple = cardioRecord(source: .appleHealth, externalID: "shared")
        let garmin = cardioRecord(source: .garminConnect, externalID: "shared")

        let summary = try WorkoutImporter.importRecords([apple, garmin], in: context)

        XCTAssertEqual(summary.importedWorkouts, 2)
        XCTAssertEqual(summary.importedSets, 2)
        XCTAssertEqual(summary.skipped, 0)

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 2)
        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(sets.count, 2)
    }

    func testImportRecordsEmptyBatchReturnsZeroSummary() throws {
        let context = makeInMemoryContext()
        let summary = try WorkoutImporter.importRecords([], in: context)
        XCTAssertEqual(summary.importedWorkouts, 0)
        XCTAssertEqual(summary.importedSets, 0)
        XCTAssertEqual(summary.skipped, 0)
    }

    func testImportRecordsThrowsWhenSaveFails() throws {
        let context = makeInMemoryContext()

        XCTAssertThrowsError(
            try WorkoutImporter.importRecords([cardioRecord()], in: context) { _ in
                throw MockSaveError.failed
            }
        ) { error in
            XCTAssertEqual(error as? WorkoutImporterError, .saveFailed)
        }

        let logs = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(logs.count, 0)
        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(sets.count, 0)
    }

    /// The ledger row is now the record of truth for workout-level detail, and
    /// every journal entry links back to it so the UI can badge and expand
    /// imported sets.
    func testImportPersistsWorkoutDetailAndLinksEntries() throws {
        let context = makeInMemoryContext()
        let record = WorkoutImportRecord(
            source: .appleHealth,
            externalID: "hk-detail",
            date: now,
            title: "Running",
            kind: .running,
            distanceMeters: 5200,
            durationSeconds: 1810,
            calories: 289,
            averageHeartRate: 152,
            maxHeartRate: 171,
            elevationAscendedMeters: 84,
            isIndoor: false,
            originName: "Garmin",
            sourceAppName: "Garmin Connect",
            deviceName: "Forerunner 265"
        )

        let summary = try WorkoutImporter.importRecords([record], in: context)
        XCTAssertEqual(summary.importedWorkouts, 1)

        let log = try XCTUnwrap(context.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(log.kind, .running)
        XCTAssertEqual(log.originName, "Garmin")
        XCTAssertEqual(log.sourceAppName, "Garmin Connect")
        XCTAssertEqual(log.deviceName, "Forerunner 265")
        XCTAssertEqual(log.distanceMeters, 5200)
        XCTAssertEqual(log.durationSeconds, 1810)
        XCTAssertEqual(log.calories, 289)
        XCTAssertEqual(log.averageHeartRate, 152)
        XCTAssertEqual(log.maxHeartRate, 171)
        XCTAssertEqual(log.elevationAscendedMeters, 84)
        XCTAssertEqual(log.isIndoor, false)
        XCTAssertEqual(log.displayOrigin, "Garmin")

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertEqual(entry.importedWorkout?.deduplicationKey, log.deduplicationKey)
        XCTAssertEqual(log.entries.count, 1)
    }

    /// Duplicating an imported set by hand produces the user's own log — the
    /// provenance link must not carry over.
    func testDuplicatedEntryDropsImportLink() throws {
        let context = makeInMemoryContext()
        _ = try WorkoutImporter.importRecords([cardioRecord()], in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertNotNil(entry.importedWorkout)

        let duplicate = entry.duplicated(at: now.addingTimeInterval(60))

        XCTAssertNil(duplicate.importedWorkout)
    }
}
