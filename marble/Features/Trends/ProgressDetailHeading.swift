import SwiftUI

/// A plain section marker for the detailed analytics stream. It uses typography
/// rather than another card or glass layer to establish hierarchy.
struct ProgressDetailHeading: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
