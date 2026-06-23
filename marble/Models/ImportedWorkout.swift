import Foundation
import SwiftData

enum ImportSource: String, Codable, CaseIterable, Identifiable {
    case appleHealth
    case garminConnect
    case strava
    /// A handwritten workout captured with the camera (or chosen from the photo
    /// library), read on-device and reviewed before it becomes journal entries.
    /// Unlike the other sources it has no remote service or `WorkoutImportProvider`;
    /// it feeds the same dedup + persistence spine through `WorkoutScanImporter`.
    case photoScan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleHealth:
            return "Apple Health"
        case .garminConnect:
            return "Garmin Connect"
        case .strava:
            return "Strava"
        case .photoScan:
            return "Scanned Workout"
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth:
            return "heart.fill"
        case .garminConnect:
            return "antenna.radiowaves.left.and.right"
        case .strava:
            return "flame.fill"
        case .photoScan:
            return "doc.text.viewfinder"
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
