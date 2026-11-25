import SwiftUI
import Charts

/// Weekly volume, one series at a time.
///
/// Weighted volume, bodyweight reps and minutes don't share a unit, so they
/// no longer share an axis: chips pick the series, bars show it in real units
/// (weight in the lifter's preferred unit), the latest or selected week is
/// emphasized, a dashed rule marks the average, and the series' best week
/// wears a trophy. Identifiers and the init signature are unchanged.
struct TrendsWeeklyVolumeChart: View {
    let derived: TrendsDerivedData
    let selectedSummary: TrendWeeklySummary?
    let chartHeight: CGFloat
    @Binding var isScrubbingChart: Bool
    let onSelectWeek: (Date) -> Void
    let onViewSets: (Date) -> Void
    let onClearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue
    @State private var chosenSeries: VolumeSeries?
    @State private var isRevealed = trendsInitiallyRevealed()

    private var weightUnit: WeightUnit { WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb }

    private var presentSeries: [VolumeSeries] {
        VolumeSeries.allCases.filter { series in
            derived.volumeData.contains { $0.series == series }
        }
    }

    private var activeSeries: VolumeSeries? {
        if let chosenSeries, presentSeries.contains(chosenSeries) { return chosenSeries }
        return presentSeries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            header
            if presentSeries.count > 1 {
                seriesPicker
            }
            if let activeSeries {
                chart(for: activeSeries)
            } else {
                Text("No volume logged in this range.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            if let selectedSummary {
                let label = TrendsDateHelper.weekLabel(start: selectedSummary.weekStart, end: selectedSummary.weekEnd)
                TrendTooltipView(
                    title: label,
                    valueText: tooltipValue(for: selectedSummary),
                    summaryText: selectedSummary.summaryText,
                    showsPR: selectedSummary.totalVolumeScore == derived.weeklyPRTotal && derived.weeklyPRTotal > 0,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for week of \(label)",
                    viewSetsIdentifier: "Trends.VolumeTooltip.ViewSets",
                    onViewSets: { onViewSets(selectedSummary.weekStart) },
                    onClear: { onClearSelection() }
                )
                .accessibilityIdentifier("Trends.VolumeTooltip")
            }
        }
        .trendsCard()
        .trendsReveal($isRevealed)
    }

    // MARK: Header

    private var header: some View {
        let series = activeSeries
        let weeks = series.map(points(for:)) ?? []
        let latest = weeks.last
        let previous = weeks.dropLast().last
        let accent = series?.color(for: colorScheme) ?? TrendsPalette.volumeWeighted.color(for: colorScheme)
        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            TrendsSectionHeader(
                title: "Weekly Volume",
                subtitle: series.map(subtitle(for:)),
                takeaway: latest.map { "\(formatted($0.value)) \(unitLabel(for: series))" },
                accent: accent
            )
            if let latest, let previous, previous.value > 0 {
                HStack(spacing: MarbleSpacing.xs) {
                    Text(latestIsThisWeek(latest.weekStart) ? "This week" : "Latest week")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    TrendsDeltaPill(
                        percent: (latest.value - previous.value) / previous.value * 100,
                        accent: accent,
                        comparisonLabel: "week before"
                    )
                }
            }
        }
    }

    private func latestIsThisWeek(_ weekStart: Date) -> Bool {
        weekStart == TrendsDateHelper.startOfWeek(for: AppEnvironment.now)
    }

    // MARK: Series picker

    private var seriesPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MarbleSpacing.xs) { seriesChips }
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) { seriesChips }
        }
    }

    private var seriesChips: some View {
        ForEach(presentSeries, id: \.self) { series in
            let isSelected = series == activeSeries
            let color = series.color(for: colorScheme)
            Button {
                MarbleHaptics.selection()
                if TrendsMotion.isEnabled(reduceMotion: reduceMotion) {
                    withAnimation(.snappy) { chosenSeries = series }
                } else {
                    chosenSeries = series
                }
            } label: {
                HStack(spacing: MarbleSpacing.xxs) {
                    TrendsLegendGlyph(color: color, symbol: series.legendSymbol)
                    Text(series.shortLabel)
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .fixedSize()
                }
                .padding(.horizontal, MarbleSpacing.s)
                .frame(minHeight: MarbleLayout.minimumTouchTarget)
                // The selected ring is two stacked fills rather than a stroked
                // capsule: a stroke's end caps render as stray vertical ticks
                // on the flat sides at some widths.
                .background {
                    if isSelected {
                        ZStack {
                            Capsule().fill(color)
                            Capsule().fill(Theme.surfaceColor(for: colorScheme)).padding(1.25)
                            Capsule().fill(TrendsPalette.wash(color, scheme: colorScheme)).padding(1.25)
                        }
                    } else {
                        Capsule().fill(Theme.chipFillColor(for: colorScheme))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(series.label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("Trends.Volume.Series.\(series.rawValue)")
        }
    }

    // MARK: Chart

    private struct WeekPoint: Identifiable {
        let weekStart: Date
        let value: Double
        var id: Date { weekStart }
    }

    private func points(for series: VolumeSeries) -> [WeekPoint] {
        derived.weeklySummaries.compactMap { summary in
            let value: Double
            switch series {
            case .weighted:
                value = LifterAnalytics.displayWeight(fromKilograms: summary.weightedVolume, in: weightUnit)
            case .reps:
                value = Double(summary.repsVolume)
            case .duration:
                value = summary.durationMinutes
            }
            return value > 0 ? WeekPoint(weekStart: summary.weekStart, value: value) : nil
        }
    }

    private func chart(for series: VolumeSeries) -> some View {
        let weeks = points(for: series)
        let summaries = derived.weeklySummaries
        let accent = series.color(for: colorScheme)
        let gold = TrendsPalette.personalRecord.color(for: colorScheme)
        let average = weeks.isEmpty ? 0 : weeks.reduce(0) { $0 + $1.value } / Double(weeks.count)
        let best = weeks.max { $0.value < $1.value }
        let emphasized = selectedSummary?.weekStart ?? weeks.last?.weekStart
        let maxValue = max(best?.value ?? 1, 1)
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.weekStart, let end = summaries.last?.weekStart else { return nil }
            return start ... end
        }()
        let chartDomain = dataRange.map { range in
            let calendar = Calendar.current
            let lower = calendar.date(byAdding: .day, value: -4, to: range.lowerBound) ?? range.lowerBound
            let upper = calendar.date(byAdding: .day, value: 11, to: range.upperBound) ?? range.upperBound
            return lower ... upper
        }
        let axisLimit = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        let axisDates = summaries.count <= axisLimit ? summaries.map(\.weekStart)
            : (0..<axisLimit).map { summaries[$0 * (summaries.count - 1) / (axisLimit - 1)].weekStart }

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Volume", isRevealed ? week.value : 0),
                        width: .ratio(0.7)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(
                        week.weekStart == emphasized
                            ? AnyShapeStyle(accent)
                            : AnyShapeStyle(accent.opacity(colorScheme == .dark ? 0.42 : 0.32))
                    )
                    .annotation(position: .top, spacing: 3) {
                        if week.id == best?.id, weeks.count > 1 {
                            Image(systemName: "trophy.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(gold)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHidden(true)
                }

                if average > 0, weeks.count > 1 {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("avg \(formatted(average))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(Theme.surfaceColor(for: colorScheme)))
                                .accessibilityHidden(true)
                        }
                        .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
            .chartYScale(domain: 0 ... maxValue * 1.18)
            .chartLegend(.hidden)
            .chartXAxis {
                if !dynamicTypeSize.isAccessibilitySize {
                    // Bars span their whole week, so center each label under
                    // its bar (mid-week) while still naming the week's start.
                    AxisMarks(values: axisDates.map { $0.addingTimeInterval(3.5 * 86_400) }) { value in
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                Text(date.addingTimeInterval(-3.5 * 86_400), format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
            }
            .chartYAxis {
                TrendsAxes.value(scheme: colorScheme, desiredCount: 3, compact: true)
            }
            .animation(TrendsMotion.isEnabled(reduceMotion: reduceMotion) ? TrendsMotion.reveal : nil, value: isRevealed)
            .animation(TrendsMotion.isEnabled(reduceMotion: reduceMotion) ? .snappy : nil, value: series)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        TrendsChartOverlay(
                            plotSize: plotFrame.size,
                            proxy: proxy,
                            dataRange: dataRange,
                            accessibilityIdentifier: "Trends.VolumeChart",
                            accessibilityLabel: "Weekly volume chart",
                            accessibilityValue: derived.volumeAccessibilityValue,
                            audioGraph: TrendsDateSeriesAudioGraph(
                                title: "Weekly volume",
                                summary: derived.volumeAccessibilityValue,
                                valueAxisName: series.shortLabel,
                                valueUnit: unitLabel(for: series),
                                series: [.init(
                                    name: series.label,
                                    points: weeks.map {
                                        .init(
                                            date: $0.weekStart,
                                            value: $0.value,
                                            valueText: "\(formatted($0.value)) \(unitLabel(for: series))"
                                        )
                                    }
                                )]
                            ),
                            isScrubbing: $isScrubbingChart
                        ) { date in
                            onSelectWeek(TrendsDateHelper.startOfWeek(for: date))
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            // Give large-text readers the full date range in wrapping text;
            // crowded axis ticks must not overlap or abbreviate to "Ja…".
            if dynamicTypeSize.isAccessibilitySize, let first = summaries.first, let last = summaries.last {
                Text(TrendsDateHelper.weekLabel(start: first.weekStart, end: last.weekEnd))
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Formatting

    private func subtitle(for series: VolumeSeries) -> String {
        switch series {
        case .weighted: "Weight × reps, in \(weightUnit.symbol)"
        case .reps: "Bodyweight reps per week"
        case .duration: "Minutes per week"
        }
    }

    private func unitLabel(for series: VolumeSeries?) -> String {
        switch series {
        case .weighted: weightUnit.symbol
        case .reps: "reps"
        case .duration: "min"
        case nil: ""
        }
    }

    private func formatted(_ value: Double) -> String {
        value >= 10_000
            ? Formatters.compactNumberText(value)
            : (Formatters.weight.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))")
    }

    private func tooltipValue(for summary: TrendWeeklySummary) -> String {
        var parts: [String] = []
        if summary.weightedVolume > 0 {
            let display = LifterAnalytics.displayWeight(fromKilograms: summary.weightedVolume, in: weightUnit)
            parts.append("\(formatted(display)) \(weightUnit.symbol) lifted")
        }
        if summary.repsVolume > 0 {
            parts.append("\(summary.repsVolume) bodyweight reps")
        }
        if summary.durationMinutes > 0 {
            parts.append("\(formatted(summary.durationMinutes)) min")
        }
        return parts.isEmpty ? "No volume" : parts.joined(separator: " · ")
    }
}

extension VolumeSeries {
    /// Chip label; `label` stays the full spoken/legend name.
    var shortLabel: String {
        switch self {
        case .weighted: "Weighted"
        case .reps: "Bodyweight"
        case .duration: "Duration"
        }
    }
}
