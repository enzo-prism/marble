import Foundation
import SwiftData

@Model
final class SupplementType {
    @Attribute(.unique) var id: UUID
    var name: String
    var defaultDose: Double?
    var unit: SupplementUnit
    var isFavorite: Bool
    var customIconEmoji: String?

    init(
        id: UUID = UUID(),
        name: String,
        defaultDose: Double? = nil,
        unit: SupplementUnit,
        isFavorite: Bool = false,
        customIconEmoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultDose = defaultDose
        self.unit = unit
        self.isFavorite = isFavorite
        self.customIconEmoji = nil
        setCustomIconEmoji(customIconEmoji)
    }
}

extension SupplementType {
    /// Stores only the first valid emoji, mirroring the exercise icon flow.
    func setCustomIconEmoji(_ emoji: String?) {
        customIconEmoji = emoji?.firstEmoji
    }

    var sanitizedCustomIconEmoji: String? {
        customIconEmoji?.firstEmoji
    }

    /// The glyph shown wherever this supplement appears: the custom emoji if set,
    /// otherwise the default pill symbol.
    var displayIcon: SupplementDisplayIcon {
        if let emoji = sanitizedCustomIconEmoji {
            return .emoji(emoji)
        }
        return .symbol(SupplementIcon.defaultSymbolName)
    }
}

