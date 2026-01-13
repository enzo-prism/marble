import SwiftUI

struct SetRowView: View {
    let entry: SetEntry

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

    var body: some View {
        let resolvedScheme = TestHooks.forcedColorScheme ?? colorScheme
        HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            Image(systemName: entry.exercise.category.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))
                .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(entry.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)

                Text(summaryLine)
                    .font(MarbleTypography.rowSubtitle)
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)

                Text(secondaryLine)
                    .font(MarbleTypography.rowMeta)
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.performedAt))
                .font(MarbleTypography.rowMeta)
                .monospacedDigit()
                .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                .accessibilityHidden(true)
        }
        .background(Theme.backgroundColor(for: resolvedScheme))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
        .accessibilityLabel(accessibilitySummary)
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
