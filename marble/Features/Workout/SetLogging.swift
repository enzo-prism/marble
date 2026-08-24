import Foundation
import SwiftData

/// Shared "log the same set again" path used by the Journal duplicate action
/// and the active workout's one-thumb complete-set rows.
enum SetLogging {
    @discardableResult
    static func repeatLatest(
        of entry: SetEntry,
        into session: WorkoutSession?,
        in context: ModelContext
    ) -> SetEntry? {
        let date = AppEnvironment.now
        let duplicate = entry.duplicated(at: date)
        context.insert(duplicate)
        copySprintMetadata(from: entry, to: duplicate, in: context)
        session?.append(duplicate, at: date)
        guard context.saveOrRollback() else { return nil }
        RestActivityController.shared.startRest(for: duplicate)
        return duplicate
    }

    static func copySprintMetadata(
        from source: SetEntry,
        to destination: SetEntry,
        in context: ModelContext
    ) {
        let sourceID = source.id
        var goalDescriptor = FetchDescriptor<SprintGoalSnapshot>(
            predicate: #Predicate { $0.setEntryID == sourceID }
        )
        goalDescriptor.fetchLimit = 1
        if let sourceGoal = (try? context.fetch(goalDescriptor))?.first {
            context.insert(SprintGoalSnapshot(
                setEntryID: destination.id,
                exerciseID: destination.exercise.id,
                distance: sourceGoal.distance,
                distanceUnit: sourceGoal.distanceUnit,
                repetitionNumber: nil,
                repetitionCount: sourceGoal.repetitionCount,
                targetLowerSeconds: sourceGoal.targetLowerSeconds,
                targetUpperSeconds: sourceGoal.targetUpperSeconds,
                isInferred: sourceGoal.isInferred,
                createdAt: destination.createdAt
            ))
        }

        var detailDescriptor = FetchDescriptor<SprintRepDetail>(
            predicate: #Predicate { $0.setEntryID == sourceID }
        )
        detailDescriptor.fetchLimit = 1
        if let sourceDetail = (try? context.fetch(detailDescriptor))?.first {
            context.insert(SprintRepDetail(
                setEntryID: destination.id,
                durationTenths: sourceDetail.durationTenths,
                targetLowerTenths: sourceDetail.targetLowerTenths,
                targetUpperTenths: sourceDetail.targetUpperTenths,
                variantID: sourceDetail.variantID,
                createdAt: destination.createdAt
            ))
        }
    }
}
