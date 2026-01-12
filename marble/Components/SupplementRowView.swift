import SwiftUI

struct SupplementRowView: View {
    let entry: SupplementEntry

    @Environment(\.colorScheme) private var colorScheme

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.type.name), \(summaryLine), \(Formatters.time.string(from: entry.takenAt))")
    }

    private var summaryLine: String {
        if let dose = entry.dose {
            let formattedDose = Formatters.dose.string(from: NSNumber(value: dose)) ?? "\(dose)"
            return "\(formattedDose) \(entry.unit.displayName)"
        }
        return "No dose"
    }
}

