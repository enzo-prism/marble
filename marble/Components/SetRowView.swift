import SwiftUI

struct SetRowView: View {
    let entry: SetEntry
    let prBadge: PersonalRecordBadge
    let accessibilityIdentifier: String?

    @Environment(\.colorScheme) private var colorScheme

    static func accessibilitySummary(for entry: SetEntry, prBadge: PersonalRecordBadge = []) -> String {
        var parts: [String] = []
        if let weight = entry.weight {
            let formattedWeight = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                parts.append("\(formattedWeight) × \(reps)")
            } else {
                parts.append(formattedWeight)
            }
        }

        if entry.weight == nil, let reps = entry.reps {
            parts.append("\(reps) reps")
        }

        if let distance = entry.distance {
            parts.append(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))
        }

        if let duration = entry.durationSeconds {
            parts.append(DateHelper.formattedDuration(seconds: duration))
        }

        let summary = parts.isEmpty ? "No metrics" : parts.joined(separator: " · ")
        var prefix = prBadge.isEmpty ? "" : "\(prBadge.accessibilityDescription). "
        if let imported = entry.importedWorkout {
            prefix += "Imported from \(imported.displayOrigin). "
        }
        return "\(prefix)\(entry.exercise.name), \(summary), RPE \(entry.difficulty), Rest \(entry.restAfterSeconds) seconds"
    }

    init(entry: SetEntry, prBadge: PersonalRecordBadge = [], accessibilityIdentifier: String? = nil) {
        self.entry = entry
        self.prBadge = prBadge
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        let resolvedScheme = TestHooks.forcedColorScheme ?? colorScheme
        let row = HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            ExerciseIconView(exercise: entry.exercise, fontSize: 20, frameSize: MarbleLayout.rowIconSize)
                .environment(\.colorScheme, resolvedScheme)

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(entry.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundColor(Theme.primaryTextColor(for: resolvedScheme))

                if !prBadge.isEmpty {
                    PRBadgeLabel(badge: prBadge)
                        .environment(\.colorScheme, resolvedScheme)
                }

                if let imported = entry.importedWorkout {
                    ImportedOriginBadge(origin: imported.displayOrigin)
                        .environment(\.colorScheme, resolvedScheme)
                }

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
            let formattedWeight = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                parts.append("\(formattedWeight) × \(reps)")
            } else {
                parts.append(formattedWeight)
            }
        }

        if entry.weight == nil, let reps = entry.reps {
            parts.append("\(reps) reps")
        }

        if let distance = entry.distance {
            parts.append(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))
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
        Self.accessibilitySummary(for: entry, prBadge: prBadge)
    }
}
