import Charts
import SwiftUI

/// A compact "now vs. start" headline for a single exercise's progress, with a sparkline so the
/// trend is graspable at a glance before the full chart.
struct ExerciseHeadlineView: View {
    let points: [ExerciseProgressPoint]
    let metricInfo: ProgressMetricInfo

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text(metricInfo.title.uppercased())
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                Text(currentSummary)
                    .font(MarbleTypography.rowTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let changeText {
                    HStack(spacing: MarbleSpacing.xxxs) {
                        Image(systemName: changeIsUp ? "arrow.up.right" : "arrow.down.right")
                            .font(MarbleTypography.smallLabel)
                        Text(changeText)
                            .font(MarbleTypography.smallLabel)
                            .monospacedDigit()
                    }
                    .foregroundStyle(changeIsUp ? Theme.toggleOnColor : Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                }
            }

            if let startText {
                Text(startText)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if points.count > 1 {
                sparkline
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("Trends.ExerciseHeadline")
    }

    private var sparkline: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Theme.dividerColor(for: colorScheme))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: sparkDomain)
        .frame(height: 36)
        .accessibilityHidden(true)
    }

    private var current: ExerciseProgressPoint? { points.last }
    private var start: ExerciseProgressPoint? { points.first }

    private var currentSummary: String {
        current?.bestSetSummary ?? "-"
    }

    private var startText: String? {
        guard points.count > 1, let start else { return nil }
        return "Started \(start.bestSetSummary) · \(DateHelper.dayLabel(for: start.date))"
    }

    private var changeFraction: Double? {
        guard points.count > 1, let start, let current, start.score > 0 else { return nil }
        return (current.score - start.score) / start.score
    }

    private var changeIsUp: Bool {
        (changeFraction ?? 0) >= 0
    }

    private var changeText: String? {
        guard let changeFraction, abs(changeFraction) > 0.005 else { return nil }
        let percent = Int((abs(changeFraction) * 100).rounded())
        guard percent > 0 else { return nil }
        return "\(percent)%"
    }

    private var sparkDomain: ClosedRange<Double> {
        let scores = points.map(\.score)
        let minScore = scores.min() ?? 0
        let maxScore = scores.max() ?? 1
        guard minScore != maxScore else {
            return (minScore - 1) ... (maxScore + 1)
        }
        let padding = (maxScore - minScore) * 0.15
        return (minScore - padding) ... (maxScore + padding)
    }

    private var accessibilityLabel: String {
        var parts = ["\(metricInfo.title), now \(currentSummary)"]
        if let changeText {
            parts.append(changeIsUp ? "up \(changeText)" : "down \(changeText)")
        }
        if let startText {
            parts.append(startText)
        }
        return parts.joined(separator: ", ")
    }
}
