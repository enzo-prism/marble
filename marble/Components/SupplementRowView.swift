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
        HStack(spacing: 12) {
            Image(systemName: "pills")
                .font(.title3)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.type.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.takenAt))
                .font(.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private var summaryLine: String {
        Self.summaryLine(for: entry)
    }
}
