import SwiftUI

/// Renders a supplement's glyph (default pill symbol or a custom emoji) in the monochrome
/// Marble style. Mirrors `ExerciseIconView` so supplement and exercise rows stay visually
/// consistent.
struct SupplementIconView: View {
    let icon: SupplementDisplayIcon
    var fontSize: CGFloat = 20
    var frameSize: CGFloat = MarbleLayout.rowIconSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

extension SupplementIconView {
    init(type: SupplementType, fontSize: CGFloat = 20, frameSize: CGFloat = MarbleLayout.rowIconSize) {
        self.init(icon: type.displayIcon, fontSize: fontSize, frameSize: frameSize)
    }
}
