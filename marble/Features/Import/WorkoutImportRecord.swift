import Foundation

enum ImportedActivityKind: String, Codable, Sendable {
    case running
    case cycling
    case swimming
    case hiking
    case walking
    case otherCardio
    case strength
    case other

    var isCardio: Bool {
        switch self {
        case .running, .cycling, .swimming, .hiking, .walking, .otherCardio:
            return true
        case .strength, .other:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .walking: return "Walking"
        case .otherCardio: return "Cardio"
        case .strength: return "Strength"
        case .other: return "Workout"
        }
    }
}

struct ImportedStrengthSet: Sendable, Identifiable {
    let id = UUID()
    let exerciseName: String
    let weightKilograms: Double?
    let reps: Int?
    let restSeconds: Int?
}

struct WorkoutImportRecord: Sendable, Identifiable {
    let id = UUID()
    let source: ImportSource
    let externalID: String
    let date: Date
    let title: String
    let kind: ImportedActivityKind
    let distanceMeters: Double?
    let durationSeconds: Int?
    let calories: Double?
    let averageHeartRate: Double?
    let strengthSets: [ImportedStrengthSet]
    /// Where the workout actually came from, when it differs from `source`. Apple Health is
    /// a hub: a single HealthKit query surfaces workouts recorded by an Apple Watch, a
    /// Garmin device, Strava, etc. We capture the true origin (e.g. "Garmin") so the UI can
    /// label each row and the imported note reads correctly. `nil` for direct connectors
    /// (Strava) where `source` already names the origin.
    let originName: String?

    var isCardio: Bool { kind.isCardio }
    var isStrength: Bool { kind == .strength }

    /// Human-readable origin for labels and notes: the explicit origin if known, else the
    /// source's own name.
    var displayOrigin: String { originName ?? source.displayName }

    init(
        source: ImportSource,
        externalID: String,
        date: Date,
        title: String,
        kind: ImportedActivityKind,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        calories: Double? = nil,
        averageHeartRate: Double? = nil,
        strengthSets: [ImportedStrengthSet] = [],
        originName: String? = nil
    ) {
        self.source = source
        self.externalID = externalID
        self.date = date
        self.title = title
        self.kind = kind
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.strengthSets = strengthSets
        self.originName = originName
    }
}
