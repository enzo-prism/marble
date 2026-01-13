import SwiftUI

struct SupplementRowView: View {
    let entry: SupplementEntry

    @Environment(\.colorScheme) private var colorScheme

    static func summaryLine(for entry: SupplementEntry) -> String {
        if let dose = entry.dose {
            let formattedDose = Formatters.dose.string(from: NSNumber(value: dose)) ?? "\(dose)"
            return "\(formattedDose) \(entry.unit.displayName)"
        }
        return "No dose"
    }

    static func accessibilityLabel(for entry: SupplementEntry) -> String {
        "\(entry.type.name), \(summaryLine(for: entry)), \(Formatters.time.string(from: entry.takenAt))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            Image(systemName: "pills")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(entry.type.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(summaryLine)
                    .font(MarbleTypography.rowSubtitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.takenAt))
                .font(MarbleTypography.rowMeta)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityHidden(true)
    }

    private var summaryLine: String {
        Self.summaryLine(for: entry)
    }
}
