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
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.title = title
        self.workoutDate = workoutDate
        self.setsImported = setsImported
        self.importedAt = importedAt
    }
}

extension ImportedWorkout {
    var source: ImportSource {
        get { ImportSource(rawValue: sourceRaw) ?? .appleHealth }
        set { sourceRaw = newValue.rawValue }
    }
}
