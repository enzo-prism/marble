import SwiftUI
import Charts

/// Weekly volume is a focused component so its marks, symbols, legend and
/// selected values can be rendered together at every supported text size.
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

    var body: some View {
        let data = derived.volumeData
        let summaries = derived.weeklySummaries
        let tooltipSummary = selectedSummary
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.weekStart,
                  let end = summaries.last?.weekStart else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = dataRange.map { range in
            let calendar = Calendar.current
            let lower = calendar.date(byAdding: .day, value: -4, to: range.lowerBound) ?? range.lowerBound
            // A weekly mark spans the entire week. Leave space after the last
            // interval so grouped bars and their symbols remain inside the plot.
            let upper = calendar.date(byAdding: .day, value: 11, to: range.upperBound) ?? range.upperBound
            return lower ... upper
        }
        let prSummary = derived.weeklyPRSummary
        let prPeakID = prSummary.flatMap { summary in
            data.filter { $0.weekStart == summary.weekStart }.max(by: { $0.value < $1.value })?.id
        }

        let volumeAccent = TrendsPalette.volumeWeighted.color(for: colorScheme)
        let presentSeries = VolumeSeries.allCases.filter { series in
            data.contains { $0.series == series }
        }
        let axisLimit = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        let axisDates = summaries.count <= axisLimit ? summaries.map(\.weekStart)
            : (0..<axisLimit).map { summaries[$0 * (summaries.count - 1) / (axisLimit - 1)].weekStart }

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Week", item.weekStart, unit: .weekOfYear),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(TrendsPalette.barGradient(item.series.color(for: colorScheme)))
                    .position(by: .value("Series", item.series.label))
                    .cornerRadius(item.series.cornerRadius)
                    .annotation(position: .top, spacing: 2) {
                        ZStack {
                            if item.id == prPeakID {
                                Circle().stroke(TrendsPalette.personalRecord.color(for: colorScheme), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            }
                            TrendsLegendGlyph(color: item.series.color(for: colorScheme), symbol: item.series.legendSymbol)
                        }
                        .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Week", selectedSummary.weekStart, unit: .weekOfYear))
                        .foregroundStyle(volumeAccent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
            .chartLegend(.hidden)
            .chartXAxis {
                if !dynamicTypeSize.isAccessibilitySize {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                        AxisValueLabel(anchor: value.as(Date.self) == axisDates.last ? .topTrailing : .topLeading) {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(Formatters.compactNumberText(doubleValue))
                        }
                    }
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(Theme.surfaceColor(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                    .padding(.trailing, MarbleSpacing.xs)
            }
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
                                valueAxisName: "Volume",
                                valueUnit: nil,
                                series: presentSeries.map { series in
                                    .init(
                                        name: series.label,
                                        points: data.filter { $0.series == series }.map {
                                            .init(
                                                date: $0.weekStart,
                                                value: $0.value,
                                                valueText: Formatters.compactNumberText($0.value)
                                            )
                                        }
                                    )
                                }
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

            if !presentSeries.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MarbleSpacing.s) { volumeLegendItems(presentSeries) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) { volumeLegendItems(presentSeries) }
                }
                .padding(.top, MarbleSpacing.xxxs)
            }

            if let tooltipSummary {
                let label = TrendsDateHelper.weekLabel(start: tooltipSummary.weekStart, end: tooltipSummary.weekEnd)
                TrendTooltipView(
                    title: label,
                    valueText: tooltipSummary.valueText,
                    summaryText: tooltipSummary.summaryText,
                    showsPR: tooltipSummary.totalVolumeScore == derived.weeklyPRTotal && derived.weeklyPRTotal > 0,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for week of \(label)",
                    viewSetsIdentifier: "Trends.VolumeTooltip.ViewSets",
                    onViewSets: {
                        onViewSets(tooltipSummary.weekStart)
                    },
                    onClear: {
                        onClearSelection()
                    }
                )
                .accessibilityIdentifier("Trends.VolumeTooltip")
            }
        }
    }

    private func volumeLegendItems(_ series: [VolumeSeries]) -> some View {
        ForEach(series, id: \.self) { item in
            TrendsLegendChip(label: item.label, color: item.color(for: colorScheme), symbol: item.legendSymbol)
        }
    }

}
