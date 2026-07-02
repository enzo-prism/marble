import Foundation
import SwiftData

/// One-row "most recently edited" descriptors, backing the render-memo
/// signatures. The signatures previously reduced over the *entire* fetched
/// array on every body evaluation (`entries.reduce(max updatedAt)`), touching
/// every model each frame during chart scrubs, toasts, and sheet churn. A
/// live one-row query (indexed on `updatedAt`) makes the same freshness check
/// O(1) per body pass, and SwiftData keeps it current automatically.
enum LatestUpdateQueries {
    static var setEntry: FetchDescriptor<SetEntry> {
        var descriptor = FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var supplementEntry: FetchDescriptor<SupplementEntry> {
        var descriptor = FetchDescriptor<SupplementEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var progressMediaAttachment: FetchDescriptor<ProgressMediaAttachment> {
        var descriptor = FetchDescriptor<ProgressMediaAttachment>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
