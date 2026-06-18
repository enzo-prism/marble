import Foundation
import SwiftData

enum ImportOutcome: Sendable, Equatable {
    case imported(setCount: Int)
    case alreadyImported
}

enum WorkoutImporter {
    struct Summary: Sendable, Equatable {
        var importedWorkouts: Int = 0
        var importedSets: Int = 0
        var skipped: Int = 0
    }

    static func alreadyImported(_ record: WorkoutImportRecord, in context: ModelContext) throws -> Bool {
        let sourceRaw = record.source.rawValue
        let externalID = record.externalID
        let descriptor = FetchDescriptor<ImportedWorkout>(
            predicate: #Predicate<ImportedWorkout> { $0.sourceRaw == sourceRaw && $0.externalID == externalID }
        )
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
            setsImported: entries.count
        )
        context.insert(log)
        return .imported(setCount: entries.count)
    }

    static func importRecords(_ records: [WorkoutImportRecord], in context: ModelContext) throws -> Summary {
        var summary = Summary()
        for record in records {
            switch try importWorkout(record, in: context) {
            case .imported(let count):
                summary.importedWorkouts += 1
                summary.importedSets += count
            case .alreadyImported:
                summary.skipped += 1
            }
        }
        context.saveOrRollback()
        return summary
    }
}
