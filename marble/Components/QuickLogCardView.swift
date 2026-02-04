import SwiftUI

struct QuickLogCardView: View {
    let entry: SetEntry?
    let onLogAgain: () -> Void
    let onEdit: () -> Void
    let onLogSet: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            if let entry {
                Text("Quick Log")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Text(entry.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(summaryLine(for: entry))
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .monospacedDigit()

                Text(lastLoggedLine(for: entry))
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                HStack(spacing: MarbleSpacing.s) {
                    Button("Log Again") {
                        onLogAgain()
                    }
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                    .accessibilityIdentifier("Journal.QuickLog.LogAgain")

                    Button("Edit") {
                        onEdit()
                    }
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                    .accessibilityIdentifier("Journal.QuickLog.Edit")
                }
            } else {
                Text("Log your first set")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text("Start building momentum.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Button("Log Set") {
                    onLogSet()
                }
                .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                .accessibilityIdentifier("Journal.QuickLog.EmptyLogSet")
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }

    private func summaryLine(for entry: SetEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weight {
            let formattedWeight = Formatters.weight.string(from: NSNumber(value: weight)) ?? "\(weight)"
            if let reps = entry.reps {
                parts.append("\(formattedWeight) \(entry.weightUnit.symbol) × \(reps)")
            } else {
                parts.append("\(formattedWeight) \(entry.weightUnit.symbol)")
            }
        }

        if entry.weight == nil, let reps = entry.reps {
            parts.append("\(reps) reps")
        }

        if let duration = entry.durationSeconds {
            parts.append(DateHelper.formattedDuration(seconds: duration))
        }

        if parts.isEmpty {
            return "No metrics"
        }

        return parts.joined(separator: " · ")
    }

    private func lastLoggedLine(for entry: SetEntry) -> String {
        let day = DateHelper.dayLabel(for: entry.performedAt)
        let time = Formatters.time.string(from: entry.performedAt)
        return "Last logged \(day) at \(time)"
    }
}
