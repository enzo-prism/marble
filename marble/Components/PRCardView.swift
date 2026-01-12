import SwiftUI

struct PRCardView: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
        )
    }
}

