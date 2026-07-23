import Foundation
import SwiftData

enum SetEntryQueries {
    /// Rows resident in the Exercise Picker's live "recents" window. Five
    /// distinct exercises are derived from the newest entries, so ~weeks of
    /// heavy logging (10–15 sets/day) is plenty for the common case; the
    /// picker previously kept an *unbounded* all-history @Query resident just
    /// to read its first few distinct exercises. `nonisolated`: a plain limit
    /// constant with no main-actor state behind it.
    nonisolated static let pickerRecentScanLimit = 200

    /// Bounded live query behind the picker's Recent row: newest first,
    /// capped at `pickerRecentScanLimit`, served by the `performedAt` index.
    /// A saturated window that still lacks enough distinct exercises falls
    /// through to `entriesForPickerRecents(window:minimumDistinct:in:)`.
    static var recentEntriesForPicker: FetchDescriptor<SetEntry> {
        var descriptor = FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = pickerRecentScanLimit
        return descriptor
    }

    /// Returns a newest-first prefix of the log guaranteed to derive the same
    /// Recent row as the full table would.
    ///
    /// Recents are the first `minimumDistinct` distinct exercises of the
    /// newest-first log, so *any* prefix containing that many distinct
    /// exercises — or the entire log, when fewer were ever trained — derives
    /// them identically. The live window satisfies that whenever it did not
    /// fill its limit (no older history exists) or already spans enough
    /// distinct exercises. The rare remainder (say 200 straight sets of one
    /// lift) escalates to a 10× window, then to the full table, so the exact
    /// pre-scoping semantics hold without the common case ever paying the
    /// unbounded fetch this replaced.
    static func entriesForPickerRecents(
        window: [SetEntry],
        minimumDistinct: Int,
        in context: ModelContext
    ) -> [SetEntry] {
        guard window.count >= pickerRecentScanLimit else { return window }
        var distinctInWindow = Set<UUID>()
        for entry in window {
            distinctInWindow.insert(entry.exercise.id)
            if distinctInWindow.count >= minimumDistinct { return window }
        }

        let escalatedLimit = pickerRecentScanLimit * 10
        var escalated = FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        escalated.fetchLimit = escalatedLimit
        if let wider = try? context.fetch(escalated) {
            let distinct = Set(wider.map { $0.exercise.id })
            // Either the wider window covers the whole log (nothing older to
            // find) or it already holds enough distinct exercises — both make
            // it equivalent to the full table for recents derivation.
            if wider.count < escalatedLimit || distinct.count >= minimumDistinct {
                return wider
            }
        }

        let all = FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        return (try? context.fetch(all)) ?? window
    }

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
