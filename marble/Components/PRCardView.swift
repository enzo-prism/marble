import SwiftUI

struct PRCardView: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    private var identifierSlug: String {
        title.replacingOccurrences(of: " ", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
                .accessibilityIdentifier("Trends.PRCard.Title.\(identifierSlug)")
            Text(value)
                .font(.headline)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
                .accessibilityIdentifier("Trends.PRCard.Value.\(identifierSlug)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
