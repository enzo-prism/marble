import Foundation

enum ExerciseIconSource: String, CaseIterable, Identifiable {
    case category
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category:
            return "Category"
        case .emoji:
            return "Emoji"
        }
    }
}

enum ExerciseDisplayIcon: Equatable {
    case symbol(String)
    case emoji(String)
}

extension String {
    /// The first emoji character in the string (or `nil`). Used to coerce a free-text
    /// field down to a single valid emoji glyph for icon inputs.
    var firstEmoji: String? {
        for character in self where character.isSingleEmoji {
            return String(character)
        }
        return nil
    }

    /// Back-compat alias used throughout the exercise icon flow.
    var firstExerciseEmoji: String? { firstEmoji }
}

private extension Character {
    var isSingleEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
            (scalar.properties.isEmoji && unicodeScalars.count > 1)
        }
    }
}
