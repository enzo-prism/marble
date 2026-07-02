import SwiftUI

/// A quiet outline capsule naming where an imported set came from ("Garmin",
/// "Apple Watch", …). Deliberately subordinate to the filled PR badge: imports
/// are provenance, not celebration. Rendered on its own line in rows so it
/// never squeezes the exercise name at accessibility type sizes.
struct ImportedOriginBadge: View {
    let origin: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(origin)
                .font(MarbleTypography.smallLabel)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .padding(.horizontal, MarbleSpacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel("Imported from \(origin)")
        .accessibilityIdentifier("ImportedBadge")
    }
}
