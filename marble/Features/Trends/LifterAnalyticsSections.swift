import SwiftUI
import Charts

// The lifter-analytics chart sections: estimated 1RM, sets per muscle group,
// rep ranges, and effort. Deliberately non-interactive (no scrub/tooltip) —
// per the HIG's progression-of-detail guidance these are glanceable summaries;
// the takeaway value lives in each section header, and VoiceOver gets a
// chart-level summary plus the framework's per-mark elements.

// MARK: - Estimated 1RM

struct OneRepMaxSectionView: View {
    let series: LifterAnalytics.OneRepMaxSeries
    let accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Estimated 1RM")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.Strength")

            if let best = series.best {
                Text("Best \(weightText(best.displayValue)) \(series.displayUnit.symbol) · \(best.bestSetSummary)")
                    .font(MarbleTypography.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.Strength.Best")
            }

            chart

            Text("Epley estimate from your best set each day, counting sets of \(LifterAnalytics.oneRepMaxRepCap) reps or fewer.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        let accent = TrendsPalette.strength.color(for: colorScheme)
        let values = series.points.map(\.displayValue)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * 0.15, maxValue * 0.02, 1)
        let domain = max(0, minValue - padding) ... (maxValue + padding)

        return Chart {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    y: .value("Estimated 1RM", point.displayValue)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(TrendsPalette.areaGradient(accent))
                .accessibilityHidden(true)
            }

            ForEach(series.points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Estimated 1RM", point.displayValue)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(Text(point.date, format: .dateTime.month(.abbreviated).day()))
                .accessibilityValue("\(weightText(point.displayValue)) \(series.displayUnit.symbol), from \(point.bestSetSummary)")
            }

            if let best = series.best {
                PointMark(
                    x: .value("Best Day", best.date),
                    y: .value("Estimated 1RM", best.displayValue)
                )
                .symbol {
                    TrendsPRDot()
                }
                .accessibilityHidden(true)
            }
        }
        .frame(height: 180)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(Theme.surfaceColor(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                .padding(.trailing, MarbleSpacing.xs)
        }
        .accessibilityLabel("Estimated one rep max chart")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("Trends.StrengthChart")
        .accessibilityChartDescriptor(TrendsDateSeriesAudioGraph(
            title: "Estimated 1RM",
            summary: accessibilityValue,
            valueAxisName: "Estimated 1RM",
            valueUnit: series.displayUnit.symbol,
            seriesName: "Estimated 1RM",
            points: series.points.map { point in
                TrendsDateSeriesAudioGraph.Point(
                    date: point.date,
                    value: point.displayValue,
                    valueText: "\(weightText(point.displayValue)) \(series.displayUnit.symbol), from \(point.bestSetSummary)"
                )
            }
        ))
    }

    private func weightText(_ value: Double) -> String {
        Formatters.weight.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Sets per muscle group

struct MuscleGroupSectionView: View {
    let groups: [LifterCoaching.MuscleGroupCoverage]
    let accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Muscle Groups")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.MuscleGroups")

            chart

            Text("Weekly hard sets per muscle (pressing counts half toward triceps and shoulders, pulling toward biceps). The 10–20 band is a guide, not a verdict — muscles with recent history but no sets in this range show as reminders.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        let accent = TrendsPalette.volumeWeighted.color(for: colorScheme)
        let band = LifterCoaching.weeklySetBand
        let maxValue = max(groups.map(\.setsPerWeek).max() ?? 1, band.upperBound)
        // Horizontal bars on purpose: orientation distinguishes the category
        // comparisons from the time-series charts above (HIG pattern).
        return Chart {
            ForEach(groups) { group in
                BarMark(
                    x: .value("Sets per week", group.setsPerWeek),
                    y: .value("Muscle Group", group.category.displayName)
                )
                .foregroundStyle(TrendsPalette.barGradient(accent))
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text(annotationText(for: group))
                        .font(MarbleTypography.smallLabel)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(group.category.displayName)
                .accessibilityValue(accessibilityText(for: group))
            }

            // The 10–20 hard-sets-per-week guide band, drawn as two quiet rules.
            RuleMark(x: .value("Band low", band.lowerBound))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .accessibilityHidden(true)
            RuleMark(x: .value("Band high", band.upperBound))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .accessibilityHidden(true)
        }
        .frame(height: max(CGFloat(groups.count) * 34, 60))
        .chartXScale(domain: 0 ... maxValue * 1.25)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Weekly sets per muscle group chart")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("Trends.MuscleGroupsChart")
        .accessibilityChartDescriptor(TrendsCategoryAudioGraph(
            title: "Weekly sets per muscle group",
            summary: accessibilityValue,
            categoryAxisName: "Muscle group",
            valueAxisName: "Hard sets per week",
            valueUnit: "sets per week",
            bars: groups.map { group in
                TrendsCategoryAudioGraph.Bar(
                    category: group.category.displayName,
                    value: group.setsPerWeek,
                    valueText: accessibilityText(for: group)
                )
            }
        ))
    }

    private func annotationText(for group: LifterCoaching.MuscleGroupCoverage) -> String {
        var parts = [String(format: "%.1f/wk", group.setsPerWeek)]
        if let daysAgo = group.lastTrainedDaysAgo {
            parts.append(daysAgo == 0 ? "today" : "\(daysAgo)d ago")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityText(for group: LifterCoaching.MuscleGroupCoverage) -> String {
        var text = String(format: "%.1f sets per week, %@", group.setsPerWeek, group.band.label)
        if let daysAgo = group.lastTrainedDaysAgo {
            text += daysAgo == 0 ? ", trained today" : ", last trained \(daysAgo) days ago"
        }
        return text
    }
}

// MARK: - Rep ranges

struct RepRangeSectionView: View {
    let buckets: [LifterAnalytics.RepRangeBucket]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Rep Ranges")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.RepRanges")

            chart

            Text("How your sets spread across strength, hypertrophy, and endurance rep ranges.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        let accent = TrendsPalette.volumeReps.color(for: colorScheme)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Sets", bucket.setCount),
                y: .value("Range", bucket.kind.displayName)
            )
            .foregroundStyle(TrendsPalette.barGradient(accent))
            .cornerRadius(3)
            .annotation(position: .trailing, alignment: .leading, spacing: MarbleSpacing.xxs) {
                Text(annotationText(for: bucket))
                    .font(MarbleTypography.smallLabel)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("\(bucket.kind.displayName), \(bucket.kind.subtitle)")
            .accessibilityValue(accessibilityText(for: bucket))
        }
        .frame(height: 128)
        .chartXScale(domain: 0 ... Double((buckets.map(\.setCount).max() ?? 1)) * 1.3)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Rep range distribution chart")
        .accessibilityValue(chartSummary)
        .accessibilityIdentifier("Trends.RepRangesChart")
        .accessibilityChartDescriptor(TrendsCategoryAudioGraph(
            title: "Rep ranges",
            summary: chartSummary,
            categoryAxisName: "Rep range",
            valueAxisName: "Sets",
            valueUnit: "sets",
            bars: buckets.map { bucket in
                TrendsCategoryAudioGraph.Bar(
                    category: "\(bucket.kind.displayName), \(bucket.kind.subtitle)",
                    value: Double(bucket.setCount),
                    valueText: accessibilityText(for: bucket)
                )
            }
        ))
    }

    /// One-sentence overview shared by the chart's accessibility value and its
    /// Audio Graph summary.
    private var chartSummary: String {
        let total = buckets.reduce(0) { $0 + $1.setCount }
        return "\(total) sets across \(buckets.count) rep ranges"
    }

    private func annotationText(for bucket: LifterAnalytics.RepRangeBucket) -> String {
        "\(bucket.setCount) · \(Int((bucket.share * 100).rounded()))%"
    }

    private func accessibilityText(for bucket: LifterAnalytics.RepRangeBucket) -> String {
        "\(bucket.setCount) sets, \(Int((bucket.share * 100).rounded())) percent"
    }
}

// MARK: - Effort (average RPE)

struct EffortSectionView: View {
    let summaries: [TrendDailySummary]
    let usesWeeks: Bool
    let accessibilityValue: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Effort")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.Effort")

            chart

            Text("Average RPE per \(usesWeeks ? "week" : "day"). Rising effort at the same loads is a fatigue cue; falling effort means you're adapting.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        let accent = TrendsPalette.effort.color(for: colorScheme)
        let values = summaries.compactMap(\.averageRPE)
        let minValue = values.min() ?? 1
        let maxValue = values.max() ?? 10
        let domain = max(1, minValue - 1) ... min(10, maxValue + 1)
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        return Chart {
            ForEach(summaries) { summary in
                if let averageRPE = summary.averageRPE {
                    LineMark(
                        x: .value("Day", summary.date),
                        y: .value("Average RPE", averageRPE)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(Text(summary.date, format: .dateTime.month(.abbreviated).day()))
                    .accessibilityValue(String(format: "Average RPE %.1f over %d sets", averageRPE, summary.count))
                }
            }

            if summaries.count > 1 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 150)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(Theme.surfaceColor(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                .padding(.trailing, MarbleSpacing.xs)
        }
        .accessibilityLabel("Effort chart")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("Trends.EffortChart")
        .accessibilityChartDescriptor(TrendsDateSeriesAudioGraph(
            title: "Effort",
            summary: accessibilityValue,
            valueAxisName: "Average RPE",
            valueUnit: nil,
            seriesName: "Average RPE",
            points: summaries.compactMap { summary in
                guard let averageRPE = summary.averageRPE else { return nil }
                return TrendsDateSeriesAudioGraph.Point(
                    date: summary.date,
                    value: averageRPE,
                    valueText: String(format: "average RPE %.1f over %d sets", averageRPE, summary.count)
                )
            }
        ))
    }
}
