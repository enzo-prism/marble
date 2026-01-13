import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: MarbleSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(MarbleTypography.emptyTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text(message)
                .font(MarbleTypography.emptyMessage)
                .lineSpacing(2)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(MarbleSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
