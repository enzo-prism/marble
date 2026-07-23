import Foundation
import SwiftData

/// Scoped fetch feeding `DailyHighlightsBuilder`.
///
/// The builder consumes exactly two slices of the log: every entry inside the
/// celebration day itself, and — for the personal-record / run-best / progress
/// comparisons — the *complete* prior history of only the exercises trained
/// that day. Entries dated after the celebration day are never read, and prior
/// entries of exercises not trained that day are grouped and then never looked
/// up. The call site nevertheless used to fetch the entire `SetEntry` table on
/// the main thread to feed it.
///
/// This performs the builder's exact projection as two indexed fetches: the
/// day's rows first (usually a handful), then prior rows restricted to that
/// day's exercise IDs. Record baselines intentionally stay *unbounded* going
/// back in time — an all-time best from years ago must still veto today's
/// "new best" — so the scoping is by exercise, not by a date margin. That is
/// why there is no safety-margin window here: any date cutoff, however
/// generous, could resurrect a beaten record and change what the card claims.
enum DailyHighlightQueries {
    /// Every entry the builder can consume for `occurrence`, sorted by
    /// `performedAt` ascending. The unsorted full-table fetch this replaces
    /// surfaced rows in store order, which left the builder's equal-value
    /// tie-breaks to insertion order; an explicit sort keeps them stable
    /// across launches. Prior rows precede day rows, mirroring the builder's
    /// own partition of `history`.
    static func history(
        for occurrence: DailyHighlightOccurrence,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SetEntry] {
        // The builder bounds the day at the next *calendar day*, not at the
        // occurrence interval's end (overnight windows extend past midnight
        // but never surface next-day entries), so mirror that exact boundary.
        let dayStart = occurrence.celebrationDay
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let dayDescriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.performedAt >= dayStart && $0.performedAt < dayEnd },
            sortBy: [SortDescriptor(\.performedAt)]
        )
        guard let dayEntries = try? context.fetch(dayDescriptor), !dayEntries.isEmpty else {
            // Nothing logged on the celebration day means the builder returns
            // nil regardless of prior history, so skip the second fetch.
            return []
        }

        let exerciseIDs = Array(Set(dayEntries.map { $0.exercise.id }))
        let priorDescriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.performedAt < dayStart && exerciseIDs.contains($0.exercise.id) },
            sortBy: [SortDescriptor(\.performedAt)]
        )
        let priorEntries = (try? context.fetch(priorDescriptor)) ?? []
        return priorEntries + dayEntries
    }
}
