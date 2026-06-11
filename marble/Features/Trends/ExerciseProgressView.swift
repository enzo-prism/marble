import Charts
import SwiftData
import SwiftUI

struct ExerciseProgressView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var range: TrendRange = .thirtyDays
    @State private var entries: [SetEntry] = []
    @State private var sheetDestination: TrendsSheetDestination?
    @State private var isScrubbingChart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    Text(exercise.name)
                        .font(MarbleTypography.sectionTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    rangePicker

                    if points.isEmpty {
                        EmptyStateView(
                            title: "No progress yet",
                            message: "Log sets for this exercise to see progress.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .accessibilityIdentifier("ExerciseProgress.EmptyState")
                    } else {
                        if let liftBests {
                            LiftBestsHighlightView(bests: liftBests)
                        }

                        ExerciseProgressChart(points: points, isScrubbing: $isScrubbingChart) { date in
                            sheetDestination = .day(date)
                        }
                    }
                }
                .padding(MarbleLayout.pagePadding)
            }
            .scrollDisabled(isScrubbingChart)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
        .sheet(item: $sheetDestination) { destination in
            Group {
                switch destination {
                case .day(let date):
                    DayDetailsSheet(date: date, entries: entriesForDay(date))
                case .week, .supplementDay, .supplementWeek:
                    EmptyView()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
        .onAppear {
            reloadEntries()
        }
        .onChange(of: range) { _, _ in
            reloadEntries()
        }
    }

    private var points: [ExerciseProgressPoint] {
        ExerciseProgressBuilder.buildPoints(entries: entries, exercise: exercise, range: range)
    }

    private var liftBests: ExerciseLiftBests? {
        ExerciseProgressBuilder.buildLiftBests(entries: entries, exercise: exercise, range: range)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("ExerciseProgress.Range")
    }

    private func reloadEntries() {
        entries = SetEntryQueries.entries(for: exercise.id, range: range, in: modelContext)
    }

    private func entriesForDay(_ date: Date) -> [SetEntry] {
        let target = Calendar.current.startOfDay(for: date)
        return entries.filter { Calendar.current.isDate($0.performedAt, inSameDayAs: target) }
    }
}

struct ExerciseProgressChart: View {
    let points: [ExerciseProgressPoint]
    @Binding var isScrubbing: Bool
    let onViewSets: (Date) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate: Date?

    init(
        points: [ExerciseProgressPoint],
        isScrubbing: Binding<Bool>,
        initialSelectedDate: Date? = nil,
        onViewSets: @escaping (Date) -> Void
    ) {
        self.points = points
        self._isScrubbing = isScrubbing
        self.onViewSets = onViewSets
        self._selectedDate = State(initialValue: initialSelectedDate)
    }

    var body: some View {
        let dataRange: ClosedRange<Date>? = {
            guard let start = points.first?.date,
                  let end = points.last?.date else {
                return nil
            }
            return start ... end
        }()
        let dateDomain = paddedDateDomain(dataRange)
        let yDomain = paddedScoreDomain

        let accent = TrendsPalette.progress.color(for: colorScheme)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("Score", point.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(TrendsPalette.areaGradient(accent))
                    .accessibilityHidden(true)
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Score", point.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                }

                ForEach(points) { point in
                    PointMark(
                        x: .value("Day", point.date),
                        y: .value("Score", point.score)
                    )
                    .symbolSize(26)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected Day", selectedPoint.date))
                        .foregroundStyle(accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("Selected Day", selectedPoint.date),
                        y: .value("Score", selectedPoint.score)
                    )
                    .symbol {
                        TrendsSelectionDot(accent: accent)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .exerciseChartDateDomain(dateDomain)
            .chartYScale(domain: yDomain)
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        TrendsChartOverlay(
                            plotSize: plotFrame.size,
                            proxy: proxy,
                            dataRange: dataRange,
                            accessibilityIdentifier: "ExerciseProgress.Chart",
                            accessibilityLabel: "Progress chart",
                            accessibilityValue: progressAccessibilityValue,
                            isScrubbing: $isScrubbing
                        ) { date in
                            selectedDate = date
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            if let selectedPoint {
                TrendTooltipView(
                    title: DateHelper.dayLabel(for: selectedPoint.date),
                    valueText: selectedPoint.bestSetSummary,
                    summaryText: selectedPoint.scoreSummary,
                    showsPR: false,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for \(DateHelper.dayLabel(for: selectedPoint.date))",
                    viewSetsIdentifier: "ExerciseProgress.Tooltip.ViewSets",
                    onViewSets: {
                        onViewSets(selectedPoint.date)
                    },
                    onClear: {
                        selectedDate = nil
                    }
                )
            }
        }
    }

    private var selectedPoint: ExerciseProgressPoint? {
        guard let selectedDate else { return nil }
        let target = Calendar.current.startOfDay(for: selectedDate)
        return points.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })
    }

    private var progressAccessibilityValue: String {
        guard !points.isEmpty else { return "No data" }
        return "\(points.count) sessions"
    }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 180
    }

    private var paddedScoreDomain: ClosedRange<Double> {
        let maxScore = max(points.map(\.score).max() ?? 1, 1)
        let padding = max(1, maxScore * 0.12)
        return 0 ... (maxScore + padding)
    }

    private func paddedDateDomain(_ range: ClosedRange<Date>?) -> ClosedRange<Date>? {
        guard let range else { return nil }
        let calendar = Calendar.current
        let lowerBound = calendar.date(byAdding: .day, value: -1, to: range.lowerBound) ?? range.lowerBound
        let upperBound = calendar.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        return lowerBound ... upperBound
    }
}

private extension View {
    @ViewBuilder
    func exerciseChartDateDomain(_ domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain)
        } else {
            self
        }
    }
}
