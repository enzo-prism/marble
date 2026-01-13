import SwiftUI

struct PlannedSetRowView: View {
    let plannedSet: PlannedSet

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            Image(systemName: plannedSet.exercise.category.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(plannedSet.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(subtitle)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plannedSet.exercise.name), planned set")
    }

    private var subtitle: String {
        let trimmed = plannedSet.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Planned set" : trimmed
    }
}
