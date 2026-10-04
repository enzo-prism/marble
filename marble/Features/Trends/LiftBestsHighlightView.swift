import SwiftUI

struct LiftBestsHighlightView: View {
    let bests: ExerciseLiftBests

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Exercise Bests")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MarbleSpacing.xs) {
                    ForEach(metrics) { metric in
                        LiftBestMetricView(metric: metric)
                    }
                }

                VStack(spacing: MarbleSpacing.xs) {
                    ForEach(metrics) { metric in
                        LiftBestMetricView(metric: metric)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("Trends.LiftBests")
    }

    private var metrics: [LiftBestMetric] {
        [
            LiftBestMetric(
                title: "Heaviest",
                value: heaviestValue,
                detail: heaviestDetail,
                identifier: "Heaviest"
            ),
            LiftBestMetric(
                title: "Most Reps",
                value: mostRepsValue,
                detail: mostRepsDetail,
                identifier: "MostReps"
            )
        ]
    }

    private var heaviestValue: String {
        guard let entry = bests.heaviestEntry, let weight = entry.weight else { return "-" }
        return entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
    }

    private var heaviestDetail: String {
        guard let entry = bests.heaviestEntry else { return "No weight logged" }
        var parts: [String] = []
        if let reps = entry.reps {
            parts.append(reps == 1 ? "1 rep" : "\(reps) reps")
        }
        parts.append(DateHelper.dayLabel(for: entry.performedAt))
        return parts.joined(separator: " · ")
    }

    private var mostRepsValue: String {
        guard let reps = bests.mostRepsEntry?.reps else { return "-" }
        return reps == 1 ? "1 rep" : "\(reps) reps"
    }

    private var mostRepsDetail: String {
        guard let entry = bests.mostRepsEntry else { return "No reps logged" }
        var parts: [String] = []
        if let weight = entry.weight {
            parts.append(entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit))
        }
        parts.append(DateHelper.dayLabel(for: entry.performedAt))
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        "\(bests.exerciseName) bests, heaviest \(heaviestValue), \(heaviestDetail), most reps \(mostRepsValue), \(mostRepsDetail)"
    }
}

private struct LiftBestMetric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let identifier: String

    var id: String { identifier }
}

private struct LiftBestMetricView: View {
    let metric: LiftBestMetric

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(metric.title)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)

            Text(metric.value)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(metric.detail)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(metric.value), \(metric.detail)")
        .accessibilityIdentifier("Trends.LiftBest.\(metric.identifier)")
    }
}
