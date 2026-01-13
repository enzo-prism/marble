import SwiftUI

struct PRCardView: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    private var identifierSlug: String {
        title.replacingOccurrences(of: " ", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            Text(title)
                .font(MarbleTypography.caption)
                .foregroundColor(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
                .accessibilityIdentifier("Trends.PRCard.Title.\(identifierSlug)")
            Text(value)
                .font(MarbleTypography.rowTitle)
                .monospacedDigit()
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
                .accessibilityIdentifier("Trends.PRCard.Value.\(identifierSlug)")
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
