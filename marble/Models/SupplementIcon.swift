import Foundation

/// How a supplement type's row icon is sourced: the default pill glyph, or a custom emoji.
enum SupplementIconSource: String, CaseIterable, Identifiable {
    case standard
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Default"
        case .emoji:
            return "Emoji"
        }
    }
}

/// The resolved glyph shown for a supplement: either an SF Symbol or a single emoji.
enum SupplementDisplayIcon: Equatable {
    case symbol(String)
    case emoji(String)
}

enum SupplementIcon {
    /// Default SF Symbol used when no custom emoji is chosen.
    static let defaultSymbolName = "pills"

    /// A spread of supplement-appropriate emoji offered as quick picks in the editor.
    static let emojiSuggestions: [String] = ["💊", "🧴", "🥤", "🐟", "☕️", "🌿", "🧂", "💧", "🍊", "🥛"]
}
