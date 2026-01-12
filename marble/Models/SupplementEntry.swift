import Foundation
import SwiftData

@Model
final class SupplementEntry {
    @Attribute(.unique) var id: UUID
    var type: SupplementType
    var takenAt: Date
    var dose: Double?
    var unit: SupplementUnit
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: SupplementType,
        takenAt: Date,
        dose: Double? = nil,
        unit: SupplementUnit,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.takenAt = takenAt
        self.dose = dose
        self.unit = unit
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

