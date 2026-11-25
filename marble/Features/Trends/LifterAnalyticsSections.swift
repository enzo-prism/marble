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

    private var changePercent: Double? {
        guard series.points.count > 1,
              let first = series.points.first?.displayValue, first > 0,
              let last = series.points.last?.displayValue
        else { return nil }
        return (last - first) / first * 100
    }

    var body: some View {
        let accent = TrendsPalette.strength.color(for: colorScheme)
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(systemName: "bolt.fill", accent: accent, size: 26)
                TrendsSectionHeader(
                    title: "Estimated 1RM",
                    takeaway: series.points.last.map { "\(weightText($0.displayValue)) \(series.displayUnit.symbol)" },
                    accent: accent,
                    identifier: "Trends.Section.Strength"
                )
            }

            HStack(spacing: MarbleSpacing.xs) {
                if let best = series.best {
                    HStack(spacing: MarbleSpacing.xxs) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TrendsPalette.personalRecord.color(for: colorScheme))
                            .accessibilityHidden(true)
                        Text("Best \(weightText(best.displayValue)) \(series.displayUnit.symbol) · \(best.bestSetSummary)")
                            .font(MarbleTypography.rowMeta)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("Trends.Strength.Best")
                }
                Spacer(minLength: 0)
                if let changePercent {
                    TrendsDeltaPill(percent: changePercent, accent: accent, comparisonLabel: "start of the range")
                }
            }

            chart

            Text("Epley estimate from your best set each day, counting sets of \(LifterAnalytics.oneRepMaxRepCap) reps or fewer.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .trendsCard()
    }

    private var chart: some View {
        let accent = TrendsPalette.strength.color(for: colorScheme)
        let values = series.points.map(\.displayValue)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * 0.15, maxValue * 0.02, 1)
        let domain = max(0, minValue - padding) ... (maxValue + padding)
        let last = series.points.last

        return Chart {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Estimated 1RM", point.displayValue)
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
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
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

            if let last, last.id != series.best?.id {
                PointMark(x: .value("Latest", last.date), y: .value("Estimated 1RM", last.displayValue))
                    .symbol { TrendsEndpointDot(accent: accent) }
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 180)
        .chartYScale(domain: domain)
        .chartXAxis { TrendsAxes.date(scheme: colorScheme) }
        .chartYAxis { TrendsAxes.value(scheme: colorScheme, desiredCount: 3) }
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

    private var inRangeCount: Int {
        groups.filter { $0.band == .inRange }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(
                    systemName: "figure.arms.open",
                    accent: TrendsPalette.bandColor(.inRange, scheme: colorScheme),
                    size: 26
                )
                TrendsSectionHeader(
                    title: "Muscle Groups",
                    takeaway: "\(inRangeCount) of \(groups.count) in range",
                    // A check only once something is actually in range; an
                    // all-below week reads as headroom, not success.
                    takeawayGlyph: inRangeCount > 0 ? "checkmark.circle.fill" : "arrow.up.right",
                    accent: TrendsPalette.bandColor(inRangeCount > 0 ? .inRange : .below, scheme: colorScheme),
                    identifier: "Trends.Section.MuscleGroups"
                )
            }

            bandLegend

            chart

            Text("Weekly hard sets per muscle (pressing counts half toward triceps and shoulders, pulling toward biceps). The 10–20 band is a guide, not a verdict — muscles with recent history but no sets in this range show as reminders.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .trendsCard()
    }

    private var bandLegend: some View {
        let bands: [LifterCoaching.VolumeBand] = [.below, .inRange, .high]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: MarbleSpacing.m) { legendItems(bands) }
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) { legendItems(bands) }
        }
        .accessibilityHidden(true)
    }

    private func legendItems(_ bands: [LifterCoaching.VolumeBand]) -> some View {
        ForEach(bands, id: \.self) { band in
            HStack(spacing: MarbleSpacing.xxs) {
                Capsule()
                    .fill(TrendsPalette.bandColor(band, scheme: colorScheme))
                    .frame(width: 14, height: 6)
                Text(band.label)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize()
            }
        }
    }

    private var chart: some View {
        let band = LifterCoaching.weeklySetBand
        let maxValue = max(groups.map(\.setsPerWeek).max() ?? 1, band.upperBound)
        // Horizontal bars on purpose: orientation distinguishes the category
        // comparisons from the time-series charts above (HIG pattern).
        return VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            ForEach(groups) { group in
                TrendsCategoryBar(
                    title: group.category.displayName,
                    valueText: annotationText(for: group),
                    accessibilityValue: accessibilityText(for: group),
                    value: group.setsPerWeek,
                    maximum: maxValue * 1.25,
                    // Color follows the band (not the muscle) so the chart reads
                    // as "where am I against the guide" at a glance.
                    accent: TrendsPalette.bandColor(group.band, scheme: colorScheme),
                    guideBand: band,
                    guideBandColor: TrendsPalette.bandColor(.inRange, scheme: colorScheme)
                )
            }
        }
        .accessibilityElement(children: .contain)
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

    private var dominant: LifterAnalytics.RepRangeBucket? {
        buckets.max { $0.share < $1.share }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(
                    systemName: "square.stack.3d.up.fill",
                    accent: TrendsPalette.volumeReps.color(for: colorScheme),
                    size: 26
                )
                TrendsSectionHeader(
                    title: "Rep Ranges",
                    takeaway: dominant.map { "\(Int(($0.share * 100).rounded()))% \($0.kind.displayName.lowercased())" },
                    identifier: "Trends.Section.RepRanges"
                )
            }

            chart

            Text("How your sets spread across strength, hypertrophy, and endurance rep ranges.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .trendsCard()
    }

    /// The whole range as one 100% bar: the mix at a glance.
    private var distributionBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(buckets.filter { $0.share > 0 }) { bucket in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(TrendsPalette.barGradient(TrendsPalette.repRange(bucket.kind).color(for: colorScheme)))
                        .frame(width: max((proxy.size.width - 6) * bucket.share, 4))
                }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private var chart: some View {
        let maximum = max(Double(buckets.map(\.setCount).max() ?? 1), 1)
        return VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            distributionBar
            ForEach(buckets) { bucket in
                TrendsCategoryBar(
                    title: bucket.kind.displayName,
                    valueText: annotationText(for: bucket),
                    accessibilityValue: "\(bucket.kind.subtitle), \(accessibilityText(for: bucket))",
                    value: Double(bucket.setCount),
                    maximum: maximum,
                    accent: TrendsPalette.repRange(bucket.kind).color(for: colorScheme)
                )
            }
        }
        .accessibilityElement(children: .contain)
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

    private var averageRPE: Double? {
        let values = summaries.compactMap(\.averageRPE)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(
                    systemName: "gauge.with.dots.needle.67percent",
                    accent: TrendsPalette.effort.color(for: colorScheme),
                    size: 26
                )
                TrendsSectionHeader(
                    title: "Effort",
                    takeaway: averageRPE.map { String(format: "Avg RPE %.1f", $0) },
                    identifier: "Trends.Section.Effort"
                )
            }

            chart

            Text("Average RPE per \(usesWeeks ? "week" : "day"). Rising effort at the same loads is a fatigue cue; falling effort means you're adapting.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .trendsCard()
    }

    private var chart: some View {
        let accent = TrendsPalette.effort.color(for: colorScheme)
        let values = summaries.compactMap(\.averageRPE)
        let minValue = values.min() ?? 1
        let maxValue = values.max() ?? 10
        let domain = max(1, minValue - 1) ... min(10, maxValue + 1)
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        let rated = summaries.filter { $0.averageRPE != nil }
        let last = rated.last
        return Chart {
            ForEach(rated) { summary in
                AreaMark(
                    x: .value("Day", summary.date),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Average RPE", summary.averageRPE ?? domain.lowerBound)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(TrendsPalette.areaGradient(accent))
                .accessibilityHidden(true)
            }

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
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
            }

            if let last, let value = last.averageRPE {
                PointMark(x: .value("Latest", last.date), y: .value("Average RPE", value))
                    .symbol { TrendsEndpointDot(accent: accent) }
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 150)
        .chartYScale(domain: domain)
        .chartXAxis { TrendsAxes.date(scheme: colorScheme) }
        .chartYAxis { TrendsAxes.value(scheme: colorScheme, desiredCount: 3) }
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
