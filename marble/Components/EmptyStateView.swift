import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
