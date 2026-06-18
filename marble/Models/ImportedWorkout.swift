import Foundation
import SwiftData

enum ImportSource: String, Codable, CaseIterable, Identifiable {
    case appleHealth
    case garminConnect

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleHealth:
            return "Apple Watch"
        case .garminConnect:
            return "Garmin Connect"
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth:
            return "applewatch"
        case .garminConnect:
            return "antenna.radiowaves.left.and.right"
        }
    }
}

@Model
final class ImportedWorkout {
    @Attribute(.unique) var id: UUID
    /// `"<source>:<externalID>"`. A database-level unique constraint so a race between
    /// two concurrent imports can't create duplicate ledger rows: SwiftData upserts on a
    /// `.unique` collision instead of inserting a second row. Always derive it via
    /// `Self.deduplicationKey(source:externalID:)` so the format stays consistent.
    @Attribute(.unique) var deduplicationKey: String
    var sourceRaw: String
    var externalID: String
    var title: String
    var workoutDate: Date
    var setsImported: Int
    var importedAt: Date

    init(
        id: UUID = UUID(),
        source: ImportSource,
        externalID: String,
        title: String,
        workoutDate: Date,
        setsImported: Int,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.deduplicationKey = Self.deduplicationKey(source: source, externalID: externalID)
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.title = title
        self.workoutDate = workoutDate
        self.setsImported = setsImported
        self.importedAt = importedAt
    }

    static func deduplicationKey(source: ImportSource, externalID: String) -> String {
        "\(source.rawValue):\(externalID)"
    }
}

extension ImportedWorkout {
    var source: ImportSource {
        get { ImportSource(rawValue: sourceRaw) ?? .appleHealth }
        set { sourceRaw = newValue.rawValue }
    }
}
