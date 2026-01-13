import SwiftUI

struct SetRowView: View {
    let entry: SetEntry
    let accessibilityIdentifier: String?

    @Environment(\.colorScheme) private var colorScheme

    static func accessibilitySummary(for entry: SetEntry) -> String {
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

        let summary = parts.isEmpty ? "No metrics" : parts.joined(separator: " · ")
        return "\(entry.exercise.name), \(summary), RPE \(entry.difficulty), Rest \(entry.restAfterSeconds) seconds"
    }

    init(entry: SetEntry, accessibilityIdentifier: String? = nil) {
        self.entry = entry
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        let resolvedScheme = TestHooks.forcedColorScheme ?? colorScheme
        let row = HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            Image(systemName: entry.exercise.category.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))
                .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(entry.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))

                Text(summaryLine)
                    .font(MarbleTypography.rowSubtitle)
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))

                Text(secondaryLine)
                    .font(MarbleTypography.rowMeta)
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.performedAt))
                .font(MarbleTypography.rowMeta)
                .monospacedDigit()
                .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(Theme.backgroundColor(for: resolvedScheme))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)

        if let accessibilityIdentifier {
            row.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            row
        }
    }

    private var summaryLine: String {
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

    private var secondaryLine: String {
        let rest = DateHelper.formattedDuration(seconds: entry.restAfterSeconds)
        return "RPE \(entry.difficulty) · Rest \(rest)"
    }

    private var accessibilitySummary: String {
        Self.accessibilitySummary(for: entry)
    }
}
