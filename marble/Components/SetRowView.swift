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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.exercise.category.symbolName)
                .font(.title3)
                .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.exercise.name)
                    .font(.headline)
                    .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)

                Text(secondaryLine)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.performedAt))
                .font(.caption)
                .foregroundColor(Theme.secondaryTextColor(for: resolvedScheme))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
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
