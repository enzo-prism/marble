import SwiftUI

struct PRCardView: View {
    let title: String
    let value: String
    /// Optional glyph + accent (Progress Details' Range Bests). Text stays on
    /// the neutral theme colors; the accent only tints the badge.
    var systemImage: String? = nil
    var accent: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var identifierSlug: String {
        title.replacingOccurrences(of: " ", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            HStack(spacing: MarbleSpacing.xs) {
                if let systemImage {
                    TrendsGlyphBadge(
                        systemName: systemImage,
                        accent: accent ?? Theme.primaryTextColor(for: colorScheme),
                        size: 24
                    )
                }
                Text(title)
                    .font(MarbleTypography.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("Trends.PRCard.Title.\(identifierSlug)")
            }
            Text(value)
                .font(TrendsFont.metricSmall)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
                .accessibilityIdentifier("Trends.PRCard.Value.\(identifierSlug)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsCard(padding: MarbleSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
