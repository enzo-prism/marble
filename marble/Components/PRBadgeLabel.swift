import SwiftUI

/// A small celebratory pill marking a personal-record set.
///
/// Monochrome by brand: a filled capsule (primary fill, background-coloured
/// text + trophy) so it reads as a reward without introducing colour onto the
/// content layer. Used in the journal list and the quick-log card.
struct PRBadgeLabel: View {
    let badge: PersonalRecordBadge

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if badge.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: MarbleSpacing.xxxs) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
                Text(badge.shortTitle)
                    .font(MarbleTypography.smallLabel)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.backgroundColor(for: colorScheme))
            .padding(.horizontal, MarbleSpacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.primaryTextColor(for: colorScheme))
            )
            .accessibilityElement()
            .accessibilityLabel(badge.accessibilityDescription)
            .accessibilityIdentifier("PRBadge")
        }
    }
}
