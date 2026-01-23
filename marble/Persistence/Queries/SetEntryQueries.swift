import Foundation
import SwiftData

enum SetEntryQueries {
    static func mostRecentEntry(for exerciseID: UUID, in context: ModelContext) -> SetEntry? {
        var descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise.id == exerciseID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func entries(for exerciseID: UUID, range: TrendRange, in context: ModelContext) -> [SetEntry] {
        if let startDate = range.startDate {
            let descriptor = FetchDescriptor<SetEntry>(
                predicate: #Predicate { $0.exercise.id == exerciseID && $0.performedAt >= startDate },
                sortBy: [SortDescriptor(\.performedAt)]
            )
            return (try? context.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise.id == exerciseID },
            sortBy: [SortDescriptor(\.performedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
