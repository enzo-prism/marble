import Foundation
import SwiftData

/// Store-wide "did anything change?" probe backed by SwiftData's persistent
/// history (WWDC24 session 10075; iOS 26 adds `sortBy` alongside `fetchLimit`
/// on `HistoryDescriptor`, which turns "newest transaction only" into a
/// one-row read of an indexed column). Every save appends a monotonically
/// increasing transaction, so the latest identifier is a complete freshness
/// token: an unchanged token means the store is byte-identical to the last
/// derivation; an advanced token means something was inserted, edited, or
/// *deleted*. Deletion is the case the one-row `updatedAt` probes in
/// `LatestUpdateQueries` cannot see (removing an old row leaves the newest
/// `updatedAt` untouched), and a full-table `fetchCount` — the previous way
/// to catch it — re-scans the whole table on every body evaluation.
enum HistoryTokenQueries {
    /// Identifier of the most recent history transaction, or `nil` when no
    /// history is available (a fresh store before its first save, or a store
    /// configuration that records no history — some in-memory test stores).
    /// `nil` is "probe unavailable", not "unchanged": callers must keep a
    /// secondary freshness signal (e.g. a `LatestUpdateQueries` probe) in
    /// their memo signature so degraded stores still refresh on edits.
    static func latestTransactionIdentifier(in context: ModelContext) -> Int64? {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetchHistory(descriptor))?.first?.transactionIdentifier
    }
}
