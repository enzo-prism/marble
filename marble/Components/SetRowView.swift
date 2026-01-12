import SwiftUI

struct SetRowView: View {
    let entry: SetEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.exercise.category.symbolName)
                .font(.title3)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.exercise.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer(minLength: 8)

            Text(Formatters.time.string(from: entry.performedAt))
                .font(.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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
        "\(entry.exercise.name), \(summaryLine), RPE \(entry.difficulty), Rest \(entry.restAfterSeconds) seconds"
    }
}

