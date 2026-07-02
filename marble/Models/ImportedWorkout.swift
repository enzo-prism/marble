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

    // Workout-level detail captured at import time (all optional and additive —
    // rows imported by earlier builds simply have them nil). The ledger is the
    // record of truth for imported detail; SetEntry rows link back via
    // `SetEntry.importedWorkout` so the journal can badge and expand them.
    var kindRaw: String?
    /// Recording brand when it differs from the source hub (e.g. "Garmin" for a
    /// workout that arrived through Apple Health).
    var originName: String?
    /// The app that wrote the sample (e.g. "Garmin Connect", "Strava").
    var sourceAppName: String?
    /// The hardware that recorded it (e.g. "Apple Watch", "Forerunner 265").
    var deviceName: String?
    var distanceMeters: Double?
    var durationSeconds: Int?
    var calories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var elevationAscendedMeters: Double?
    var isIndoor: Bool?

    /// The journal entries this import produced. Deleting the ledger row leaves
    /// the entries in place (nullify); deleting an entry just unlinks it.
    @Relationship(deleteRule: .nullify, inverse: \SetEntry.importedWorkout)
    var entries: [SetEntry] = []

    init(
        id: UUID = UUID(),
        source: ImportSource,
        externalID: String,
        title: String,
        workoutDate: Date,
        setsImported: Int,
        importedAt: Date = Date(),
        kind: ImportedActivityKind? = nil,
        originName: String? = nil,
        sourceAppName: String? = nil,
        deviceName: String? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        calories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        elevationAscendedMeters: Double? = nil,
        isIndoor: Bool? = nil
    ) {
        self.id = id
        self.deduplicationKey = Self.deduplicationKey(source: source, externalID: externalID)
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.title = title
        self.workoutDate = workoutDate
        self.setsImported = setsImported
        self.importedAt = importedAt
        self.kindRaw = kind?.rawValue
        self.originName = originName
        self.sourceAppName = sourceAppName
        self.deviceName = deviceName
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationAscendedMeters = elevationAscendedMeters
        self.isIndoor = isIndoor
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

    var kind: ImportedActivityKind? {
        get { kindRaw.flatMap(ImportedActivityKind.init(rawValue:)) }
        set { kindRaw = newValue?.rawValue }
    }

    /// Human-readable origin for labels: the recording brand if known, else the
    /// source hub's own name.
    var displayOrigin: String { originName ?? source.displayName }
}
