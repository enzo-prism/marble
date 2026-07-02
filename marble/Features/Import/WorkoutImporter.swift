import Foundation
import SwiftData

nonisolated enum ImportOutcome: Sendable, Equatable {
    case imported(setCount: Int)
    case alreadyImported
}

nonisolated enum WorkoutImporterError: LocalizedError, Equatable {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Imported workouts could not be saved."
        }
    }
}

enum WorkoutImporter {
    struct Summary: Sendable, Equatable {
        var importedWorkouts: Int = 0
        var importedSets: Int = 0
        var skipped: Int = 0
    }

    static func alreadyImported(_ record: WorkoutImportRecord, in context: ModelContext) throws -> Bool {
        let key = ImportedWorkout.deduplicationKey(source: record.source, externalID: record.externalID)
        var descriptor = FetchDescriptor<ImportedWorkout>(
            predicate: #Predicate<ImportedWorkout> { $0.deduplicationKey == key }
        )
        descriptor.fetchLimit = 1
        return !(try context.fetch(descriptor)).isEmpty
    }

    static func importWorkout(_ record: WorkoutImportRecord, in context: ModelContext) throws -> ImportOutcome {
        if try alreadyImported(record, in: context) {
            return .alreadyImported
        }
        let entries = try WorkoutImportMapper.makeSetEntries(for: record, in: context)
        let log = ImportedWorkout(
            source: record.source,
            externalID: record.externalID,
            title: record.title,
            workoutDate: record.date,
            setsImported: entries.count,
            kind: record.kind,
            originName: record.originName,
            sourceAppName: record.sourceAppName,
            deviceName: record.deviceName,
            distanceMeters: record.distanceMeters,
            durationSeconds: record.durationSeconds,
            calories: record.calories,
            averageHeartRate: record.averageHeartRate,
            maxHeartRate: record.maxHeartRate,
            elevationAscendedMeters: record.elevationAscendedMeters,
            isIndoor: record.isIndoor
        )
        context.insert(log)
        // Link the journal entries back to their ledger row so the journal can
        // badge imported sets and expand the full workout detail.
        for entry in entries {
            entry.importedWorkout = log
        }
        return .imported(setCount: entries.count)
    }

    static func importRecords(
        _ records: [WorkoutImportRecord],
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Summary {
        var summary = Summary()
        var seenKeys = Set<String>(minimumCapacity: records.count)
        for record in records {
            let key = ImportedWorkout.deduplicationKey(source: record.source, externalID: record.externalID)
            guard seenKeys.insert(key).inserted else {
                summary.skipped += 1
                continue
            }
            switch try importWorkout(record, in: context) {
            case .imported(let count):
                summary.importedWorkouts += 1
                summary.importedSets += count
            case .alreadyImported:
                summary.skipped += 1
            }
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw WorkoutImporterError.saveFailed
        }
        return summary
    }
}
