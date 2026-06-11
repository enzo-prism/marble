import SwiftUI

struct ExerciseIconView: View {
    let icon: ExerciseDisplayIcon
    var fontSize: CGFloat = 20
    var frameSize: CGFloat = MarbleLayout.rowIconSize

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: fontSize * scale, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: fontSize * scale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: frameSize * scale, height: frameSize * scale)
        .accessibilityHidden(true)
    }
}

extension ExerciseIconView {
    init(exercise: Exercise, fontSize: CGFloat = 20, frameSize: CGFloat = MarbleLayout.rowIconSize) {
        self.init(icon: exercise.displayIcon, fontSize: fontSize, frameSize: frameSize)
    }
}
