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
    var firstExerciseEmoji: String? {
        for character in self {
            if character.isExerciseEmoji {
                return String(character)
            }
        }
        return nil
    }
}

private extension Character {
    var isExerciseEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
            (scalar.properties.isEmoji && unicodeScalars.count > 1)
        }
    }
}
