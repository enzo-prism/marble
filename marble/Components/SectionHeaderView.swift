import SwiftUI

struct SectionHeaderView: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(MarbleTypography.sectionTitle)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.backgroundColor(for: colorScheme))
    }
}
