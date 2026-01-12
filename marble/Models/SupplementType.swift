import Foundation
import SwiftData

@Model
final class SupplementType {
    @Attribute(.unique) var id: UUID
    var name: String
    var defaultDose: Double?
    var unit: SupplementUnit
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        defaultDose: Double? = nil,
        unit: SupplementUnit,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.defaultDose = defaultDose
        self.unit = unit
        self.isFavorite = isFavorite
    }
}

