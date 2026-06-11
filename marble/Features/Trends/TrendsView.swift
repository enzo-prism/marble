import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Declared (not read) so the environment change invalidates this view:
    // range buckets anchored to "today" must re-derive on a new day.
    @Environment(\.marbleActiveDay) private var activeDay

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SupplementEntry.takenAt, order: .reverse)
    private var supplementEntries: [SupplementEntry]

    @Query(sort: \SupplementType.name)
    private var supplementTypes: [SupplementType]

    @State private var range: TrendRange = .thirtyDays
    @State private var selectedExerciseID: UUID?
    @State private var selectedSupplementTypeID: UUID?
    @State private var selectedDay: Date?
    @State private var selectedWeekStart: Date?
    @State private var selectedSupplementDay: Date?
    @State private var sheetDestination: TrendsSheetDestination?
    @State private var isPresentingExerciseSearch = false
    @State private var isScrubbingChart = false

    init(
        initialRange: TrendRange = .thirtyDays,
        initialExercise: Exercise? = nil,
        initialSelectedDay: Date? = nil,
        initialSelectedWeekStart: Date? = nil,
        initialSupplementType: SupplementType? = nil,
        initialSelectedSupplementDay: Date? = nil
    ) {
        _range = State(initialValue: initialRange)
        _selectedExerciseID = State(initialValue: initialExercise?.id)
        _selectedDay = State(initialValue: initialSelectedDay)
        _selectedWeekStart = State(initialValue: initialSelectedWeekStart)
        _selectedSupplementTypeID = State(initialValue: initialSupplementType?.id)
        _selectedSupplementDay = State(initialValue: initialSelectedSupplementDay)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let derived = makeDerivedData()
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    let hasSetData = !derived.filteredEntries.isEmpty
                    let hasSupplementData = !derived.filteredSupplementEntries.isEmpty

                    rangePicker
                    if let liftBests = derived.liftBests {
                        LiftBestsHighlightView(bests: liftBests)
                    }
                    if hasSetData || hasSupplementData {
                        trendSummaryStrip(derived: derived)
                    }

                    if !hasSetData && !hasSupplementData {
                        EmptyStateView(
                            title: "No trend data yet",
                            message: "Log sets or supplements to see trends.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                            .accessibilityIdentifier("Trends.EmptyState")
                    } else {
                        if hasSetData {
                            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                Text("Consistency")
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                consistencyChart(derived: derived)
                            }

                            if selectedExercise != nil {
                                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                    Text("Progress")
                                        .font(MarbleTypography.sectionTitle)
                                        .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                    if derived.progressPoints.isEmpty {
                                        Text("No progress yet")
                                            .font(MarbleTypography.rowMeta)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    } else {
                                        ExerciseProgressChart(points: derived.progressPoints, isScrubbing: $isScrubbingChart) { date in
                                            sheetDestination = .day(date)
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                Text("Weekly Volume")
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                volumeChart(derived: derived)
                            }
                        } else {
                            Text("No workout data for this range.")
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }

                        supplementsSection(derived: derived)
                            .padding(.top, MarbleSpacing.xxl)

                        if hasSetData {
                            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                Text("PRs")
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                    .accessibilityHidden(true)
                                prCards(derived: derived)
                            }
                        }
                    }
                }
                .padding(MarbleLayout.pagePadding)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: MarbleSpacing.xxl)
                    .accessibilityHidden(true)
            }
            .scrollDisabled(isScrubbingChart)
            .accessibilityIdentifier("Trends.Scroll")
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Trends")
            .navigationSubtitle(selectedExerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    exerciseSearchButton
                    AddSetToolbarButton()
                }
            }
        }
        .sheet(item: $sheetDestination) { destination in
            Group {
                switch destination {
                case .day(let date):
                    DayDetailsSheet(date: date, entries: entriesForDay(date))
                case .week(let weekStart):
                    let weekEnd = TrendsDateHelper.endOfWeek(for: weekStart)
                    WeekDetailsSheet(weekStart: weekStart, weekEnd: weekEnd, entries: entriesForWeek(weekStart: weekStart))
                case .supplementDay(let date):
                    SupplementDayDetailsSheet(date: date, entries: supplementEntriesForDay(date))
                case .supplementWeek(let weekStart):
                    SupplementDayDetailsSheet(
                        date: weekStart,
                        endDate: TrendsDateHelper.endOfWeek(for: weekStart),
                        entries: supplementEntriesForWeek(weekStart: weekStart)
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
        .sheet(isPresented: $isPresentingExerciseSearch) {
            NavigationStack {
                TrendsExerciseSearchView(
                    exercises: exercises,
                    entries: entries,
                    selectedExerciseID: $selectedExerciseID
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
        .onChange(of: range) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedExerciseID) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedSupplementTypeID) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedDay) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit else { return }
            if let day = newValue {
                openConsistencyDrilldown(for: day)
            }
        }
        .onChange(of: selectedWeekStart) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit else { return }
            if let weekStart = newValue {
                sheetDestination = .week(weekStart)
            }
        }
        .onChange(of: selectedSupplementDay) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit else { return }
            if let day = newValue {
                openSupplementDrilldown(for: day)
            }
        }
    }

    private func makeDerivedData() -> TrendsDerivedData {
        TrendsDerivedData.build(
            entries: entries,
            supplementEntries: supplementEntries,
            selectedExercise: selectedExercise,
            selectedSupplementType: selectedSupplementType,
            range: range
        )
    }

    /// Long ranges aggregate the consistency and supplement charts to weekly
    /// buckets so mark counts stay proportional to what the chart can show.
    private var consistencyUsesWeeks: Bool {
        range == .oneYear || range == .all
    }

    private func openConsistencyDrilldown(for bucketStart: Date) {
        sheetDestination = consistencyUsesWeeks ? .week(bucketStart) : .day(bucketStart)
    }

    private func openSupplementDrilldown(for bucketStart: Date) {
        sheetDestination = consistencyUsesWeeks ? .supplementWeek(bucketStart) : .supplementDay(bucketStart)
    }

    private func consistencyBucketTitle(for bucketStart: Date) -> String {
        consistencyUsesWeeks
            ? TrendsDateHelper.weekLabel(start: bucketStart, end: TrendsDateHelper.endOfWeek(for: bucketStart))
            : DateHelper.dayLabel(for: bucketStart)
    }

    private var selectedExercise: Exercise? {
        guard let selectedExerciseID else { return nil }
        return exercises.first { $0.id == selectedExerciseID }
    }

    private var selectedSupplementType: SupplementType? {
        guard let selectedSupplementTypeID else { return nil }
        return supplementTypes.first { $0.id == selectedSupplementTypeID }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("Trends.Range")
    }

    private var exerciseSearchButton: some View {
        Button {
            isPresentingExerciseSearch = true
        } label: {
            ScaledSymbol(
                systemName: selectedExercise == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill",
                size: 17,
                weight: .semibold
            )
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("Trends.ExerciseSearchButton")
        .accessibilityLabel("Filter Exercise")
        .accessibilityValue(selectedExerciseName)
    }

    private var selectedExerciseName: String {
        selectedExercise?.name ?? "All Exercises"
    }

    private var supplementPicker: some View {
        Picker("Supplement", selection: $selectedSupplementTypeID) {
            Text("All Supplements").tag(UUID?.none)
            ForEach(supplementTypes) { type in
                Text(type.name).tag(type.id as UUID?)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.primaryTextColor(for: colorScheme))
        .accessibilityIdentifier("Trends.SupplementFilter")
        .accessibilityValue(selectedSupplementType?.name ?? "All Supplements")
    }

    private func trendSummaryStrip(derived: TrendsDerivedData) -> some View {
        let items = trendSummaryItems(derived: derived)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: MarbleSpacing.xs) {
                ForEach(items) { item in
                    TrendSummaryItemView(item: item)
                }
            }

            VStack(spacing: MarbleSpacing.xs) {
                ForEach(items) { item in
                    TrendSummaryItemView(item: item)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Trends.Summary")
    }

    private func trendSummaryItems(derived: TrendsDerivedData) -> [TrendSummaryItem] {
        let bestWeek = derived.weeklySummaries.max { $0.setCount < $1.setCount }
        let supplementLogs = derived.filteredSupplementEntries.count
        var items: [TrendSummaryItem] = [
            TrendSummaryItem(
                title: "Sets",
                value: "\(derived.filteredEntries.count)",
                detail: "\(derived.activeDayCount) active days",
                accent: TrendsPalette.consistency.color(for: colorScheme)
            ),
            TrendSummaryItem(
                title: "Best Week",
                value: bestWeek.map { "\($0.setCount)" } ?? "-",
                detail: bestWeek.map { TrendsDateHelper.weekLabel(start: $0.weekStart, end: $0.weekEnd) } ?? "No week yet",
                accent: TrendsPalette.volumeWeighted.color(for: colorScheme)
            )
        ]
        if supplementLogs > 0 {
            items.append(TrendSummaryItem(
                title: "Supplements",
                value: "\(supplementLogs)",
                detail: selectedSupplementType?.name ?? "All types",
                accent: TrendsPalette.supplements.color(for: colorScheme)
            ))
        }
        return items
    }

    private func consistencyChart(derived: TrendsDerivedData) -> some View {
        let summaries = derived.consistencySummaries
        let selectedSummary = selectedConsistencySummary(in: derived)
        let tooltipSummary = selectedSummary
        let prSummary = derived.consistencyPRSummary
        let yDomain = paddedNumericDomain(maxValue: Double(max(derived.consistencyPRCount, 1)))
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.date,
                  let end = summaries.last?.date else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: consistencyUsesWeeks ? 4 : 1)
        let accent = TrendsPalette.consistency.color(for: colorScheme)
        let activeBuckets = summaries.filter { $0.count > 0 }
        let averageSets: Double = activeBuckets.isEmpty
            ? 0
            : Double(activeBuckets.reduce(0) { $0 + $1.count }) / Double(activeBuckets.count)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(summaries) { item in
                    AreaMark(
                        x: .value("Day", item.date),
                        y: .value("Sets", item.count)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(TrendsPalette.areaGradient(accent))
                    .accessibilityHidden(true)
                }

                ForEach(summaries) { item in
                    LineMark(
                        x: .value("Day", item.date),
                        y: .value("Sets", item.count)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                }

                if averageSets > 0, summaries.count > 1 {
                    RuleMark(y: .value("Average", averageSets))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .accessibilityHidden(true)
                }

                if let prSummary, prSummary.count > 0 {
                    PointMark(
                        x: .value("PR Day", prSummary.date),
                        y: .value("Sets", prSummary.count)
                    )
                    .symbol {
                        TrendsPRDot()
                    }
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Day", selectedSummary.date))
                        .foregroundStyle(accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("Selected Day", selectedSummary.date),
                        y: .value("Sets", selectedSummary.count)
                    )
                    .symbol {
                        TrendsSelectionDot(accent: accent)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        TrendsChartOverlay(
                            plotSize: plotFrame.size,
                            proxy: proxy,
                            dataRange: dataRange,
                            accessibilityIdentifier: "Trends.ConsistencyChart",
                            accessibilityLabel: "Consistency chart",
                            accessibilityValue: consistencyAccessibilityValue(for: summaries),
                            isScrubbing: $isScrubbingChart
                        ) { date in
                            selectDay(date)
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            if let tooltipSummary {
                TrendTooltipView(
                    title: consistencyBucketTitle(for: tooltipSummary.date),
                    valueText: setsLabel(for: tooltipSummary.count),
                    summaryText: tooltipSummary.summaryText,
                    showsPR: tooltipSummary.count == derived.consistencyPRCount && derived.consistencyPRCount > 0,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for \(consistencyBucketTitle(for: tooltipSummary.date))",
                    viewSetsIdentifier: "Trends.ConsistencyTooltip.ViewSets",
                    onViewSets: {
                        openConsistencyDrilldown(for: tooltipSummary.date)
                    },
                    onClear: {
                        selectedDay = nil
                    }
                )
                .accessibilityIdentifier("Trends.ConsistencyTooltip")
            }
        }
    }

    private func volumeChart(derived: TrendsDerivedData) -> some View {
        let data = derived.volumeData
        let summaries = derived.weeklySummaries
        let selectedSummary = selectedWeeklySummary(in: derived)
        let tooltipSummary = selectedSummary
        let prSummary = derived.weeklyPRSummary
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.weekStart,
                  let end = summaries.last?.weekStart else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: 4)

        let volumeAccent = TrendsPalette.volumeWeighted.color(for: colorScheme)
        let presentSeries = VolumeSeries.allCases.filter { series in
            data.contains { $0.series == series }
        }

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Week", item.weekStart),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(TrendsPalette.barGradient(item.series.color(for: colorScheme)))
                    .position(by: .value("Series", item.series.label))
                    .cornerRadius(3)
                    .accessibilityHidden(true)
                }

                if let prSummary, prSummary.totalVolumeScore > 0 {
                    PointMark(
                        x: .value("PR Week", prSummary.weekStart),
                        y: .value("Value", prSummary.maxSeriesValue)
                    )
                    .symbol {
                        TrendsPRDot()
                    }
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Week", selectedSummary.weekStart))
                        .foregroundStyle(volumeAccent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("Selected Week", selectedSummary.weekStart),
                        y: .value("Value", selectedSummary.maxSeriesValue)
                    )
                    .symbol {
                        TrendsSelectionDot(accent: volumeAccent)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
            .chartLegend(.hidden)
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
                            accessibilityValue: volumeAccessibilityValue(for: data),
                            isScrubbing: $isScrubbingChart
                        ) { date in
                            selectWeekStart(date)
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            if !presentSeries.isEmpty {
                HStack(spacing: MarbleSpacing.s) {
                    ForEach(presentSeries, id: \.self) { series in
                        TrendsLegendChip(label: series.label, color: series.color(for: colorScheme))
                    }
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
                        sheetDestination = .week(tooltipSummary.weekStart)
                    },
                    onClear: {
                        selectedWeekStart = nil
                    }
                )
                .accessibilityIdentifier("Trends.VolumeTooltip")
            }
        }
    }

    private func supplementsSection(derived: TrendsDerivedData) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Supplements")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Spacer(minLength: MarbleSpacing.s)

                supplementPicker
            }

            if derived.filteredSupplementEntries.isEmpty {
                Text("No supplement data yet")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.SupplementsEmpty")
            } else {
                supplementsChart(derived: derived)
            }
        }
    }

    private func supplementsChart(derived: TrendsDerivedData) -> some View {
        let summaries = derived.supplementSummaries
        let selectedSummary = selectedSupplementSummary(in: derived)
        let yDomain = paddedNumericDomain(maxValue: summaries.map(\.chartValue).max() ?? 1)
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.date,
                  let end = summaries.last?.date else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: 1)

        let accent = TrendsPalette.supplements.color(for: colorScheme)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(summaries) { item in
                    AreaMark(
                        x: .value("Day", item.date),
                        y: .value("Value", item.chartValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(TrendsPalette.areaGradient(accent))
                    .accessibilityHidden(true)
                }

                ForEach(summaries) { item in
                    LineMark(
                        x: .value("Day", item.date),
                        y: .value("Value", item.chartValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                }

                ForEach(summaries.filter { $0.count > 0 }) { item in
                    PointMark(
                        x: .value("Day", item.date),
                        y: .value("Value", item.chartValue)
                    )
                    .symbolSize(24)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Day", selectedSummary.date))
                        .foregroundStyle(accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("Selected Day", selectedSummary.date),
                        y: .value("Value", selectedSummary.chartValue)
                    )
                    .symbol {
                        TrendsSelectionDot(accent: accent)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        TrendsChartOverlay(
                            plotSize: plotFrame.size,
                            proxy: proxy,
                            dataRange: dataRange,
                            accessibilityIdentifier: "Trends.SupplementsChart",
                            accessibilityLabel: "Supplements chart",
                            accessibilityValue: supplementAccessibilityValue(for: summaries, mode: derived.supplementDisplayMode),
                            isScrubbing: $isScrubbingChart
                        ) { date in
                            selectSupplementDay(date, derived: derived)
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            if let selectedSummary {
                let label = consistencyBucketTitle(for: selectedSummary.date)
                TrendTooltipView(
                    title: label,
                    valueText: selectedSummary.valueText,
                    summaryText: selectedSummary.summaryText,
                    showsPR: false,
                    viewSetsLabel: "View logs",
                    viewSetsAccessibilityLabel: "View supplement logs for \(label)",
                    viewSetsIdentifier: "Trends.SupplementsTooltip.ViewLogs",
                    onViewSets: {
                        openSupplementDrilldown(for: selectedSummary.date)
                    },
                    onClear: {
                        selectedSupplementDay = nil
                    }
                )
                .accessibilityIdentifier("Trends.SupplementsTooltip")
            }
        }
    }

    private func prCards(derived: TrendsDerivedData) -> some View {
        let filteredEntries = derived.filteredEntries
        let bestWeightEntry = filteredEntries
            .filter { $0.weight != nil }
            .max { (lhs, rhs) in
                (lhs.weight ?? 0) < (rhs.weight ?? 0)
            }
        // Compare in meters so a 6 mi run beats a 200 m sprint regardless of
        // the unit each entry was logged in.
        let bestDistanceEntry = filteredEntries
            .filter { $0.distance != nil }
            .max { (lhs, rhs) in
                lhs.distanceUnit.meters(from: lhs.distance ?? 0) < rhs.distanceUnit.meters(from: rhs.distance ?? 0)
            }
        let fastestSpeedEntry = filteredEntries
            .filter { ($0.distance ?? 0) > 0 && ($0.durationSeconds ?? 0) > 0 }
            .max { lhs, rhs in
                let lhsSpeed = lhs.distanceUnit.meters(from: lhs.distance ?? 0) / Double(max(lhs.durationSeconds ?? 1, 1))
                let rhsSpeed = rhs.distanceUnit.meters(from: rhs.distance ?? 0) / Double(max(rhs.durationSeconds ?? 1, 1))
                return lhsSpeed < rhsSpeed
            }
        let bestReps = filteredEntries.compactMap { $0.reps }.max()
        let bestDuration = filteredEntries.compactMap { $0.durationSeconds }.max()
        let sessionCount = derived.activeDayCount
        let showsDistancePRs = bestDistanceEntry != nil

        let firstCard = PRCardMetric(
            title: showsDistancePRs ? "Best Distance" : "Best Weight",
            value: showsDistancePRs
                ? bestDistanceEntry.map { $0.exercise.formattedDistanceSummary($0.distance ?? 0, unit: $0.distanceUnit) } ?? "-"
                : bestWeightEntry.map { $0.exercise.formattedWeightSummary($0.weight ?? 0, unit: $0.weightUnit) } ?? "-"
        )
        let secondCard = PRCardMetric(
            title: showsDistancePRs ? "Fastest Pace" : "Best Reps",
            value: showsDistancePRs
                ? fastestSpeedEntry.flatMap { fastestEntry in
                    Formatters.paceText(
                        distance: fastestEntry.distance ?? 0,
                        unit: fastestEntry.distanceUnit,
                        durationSeconds: fastestEntry.durationSeconds ?? 0
                    )
                } ?? "-"
                : bestReps.map { "\($0) reps" } ?? "-"
        )
        let thirdCard = PRCardMetric(title: "Longest Duration", value: bestDuration.map { DateHelper.formattedDuration(seconds: $0) } ?? "-")
        let fourthCard = PRCardMetric(title: "Sessions", value: "\(sessionCount)")

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    PRCardView(title: firstCard.title, value: firstCard.value)
                    PRCardView(title: secondCard.title, value: secondCard.value)
                    PRCardView(title: thirdCard.title, value: thirdCard.value)
                    PRCardView(title: fourthCard.title, value: fourthCard.value)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        PRCardView(title: firstCard.title, value: firstCard.value)
                        PRCardView(title: secondCard.title, value: secondCard.value)
                    }
                    HStack(spacing: 12) {
                        PRCardView(title: thirdCard.title, value: thirdCard.value)
                        PRCardView(title: fourthCard.title, value: fourthCard.value)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prCardsAccessibilityLabel(
            bestWeightEntry: bestWeightEntry,
            bestDistanceEntry: bestDistanceEntry,
            fastestSpeedEntry: fastestSpeedEntry,
            bestReps: bestReps,
            bestDuration: bestDuration,
            sessionCount: sessionCount
        ))
        .accessibilityIdentifier("Trends.PRCards")
    }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 180
    }

    private func selectedConsistencySummary(in derived: TrendsDerivedData) -> TrendDailySummary? {
        guard let selectedDay else { return nil }
        guard let nearest = nearestDay(to: selectedDay, in: derived.consistencySummaries) else { return nil }
        return derived.consistencySummaries.first { $0.date == nearest }
    }

    private func selectedWeeklySummary(in derived: TrendsDerivedData) -> TrendWeeklySummary? {
        guard let selectedWeekStart else { return nil }
        guard let nearest = nearestWeekStart(to: selectedWeekStart, in: derived.weeklySummaries) else { return nil }
        return derived.weeklySummaries.first { $0.weekStart == nearest }
    }

    private func selectedSupplementSummary(in derived: TrendsDerivedData) -> SupplementDailySummary? {
        guard let selectedSupplementDay else { return nil }
        guard let nearest = nearestSupplementDay(to: selectedSupplementDay, in: derived.supplementSummaries) else { return nil }
        return derived.supplementSummaries.first { $0.date == nearest }
    }

    private func nearestDay(to date: Date, in data: [TrendDailySummary]) -> Date? {
        guard !data.isEmpty else { return nil }
        let target = Calendar.current.startOfDay(for: date)
        return data.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })?.date
    }

    private func nearestSupplementDay(to date: Date, in data: [SupplementDailySummary]) -> Date? {
        guard !data.isEmpty else { return nil }
        let target = Calendar.current.startOfDay(for: date)
        return data.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })?.date
    }

    private func nearestWeekStart(to date: Date, in data: [TrendWeeklySummary]) -> Date? {
        guard !data.isEmpty else { return nil }
        let target = TrendsDateHelper.startOfWeek(for: date)
        return data.min(by: { abs($0.weekStart.timeIntervalSince(target)) < abs($1.weekStart.timeIntervalSince(target)) })?.weekStart
    }

    private func consistencyAccessibilityValue(for data: [TrendDailySummary]) -> String {
        guard !data.isEmpty else { return "No data" }
        let totalSets = data.reduce(0) { $0 + $1.count }
        let activeBuckets = data.filter { $0.count > 0 }.count
        let bucketLabel = consistencyUsesWeeks ? "active weeks" : "active days"
        return "\(totalSets) sets over \(activeBuckets) \(bucketLabel)"
    }

    private func volumeAccessibilityValue(for data: [VolumeDatum]) -> String {
        guard !data.isEmpty else { return "No data" }
        let totals = Dictionary(grouping: data, by: \.series).mapValues { items in
            items.reduce(0.0) { $0 + $1.value }
        }
        let weekCount = Set(data.map(\.weekStart)).count
        let parts: [String] = [
            totals[.weighted].map { "Weighted \(Int($0))" },
            totals[.reps].map { "Reps \(Int($0))" },
            totals[.duration].map { "Duration \(Int($0)) minutes" }
        ].compactMap { $0 }
        let summary = parts.joined(separator: ", ")
        if summary.isEmpty {
            return "\(weekCount) weeks of volume"
        }
        return "\(summary) across \(weekCount) weeks"
    }

    private func supplementAccessibilityValue(for data: [SupplementDailySummary], mode: SupplementTrendDisplayMode) -> String {
        guard !data.isEmpty else { return "No data" }
        let bucketLabel = consistencyUsesWeeks ? "weeks" : "days"
        switch mode {
        case .dose(let unit):
            let total = data.reduce(0.0) { $0 + $1.totalDose }
            let formatted = Formatters.dose.string(from: NSNumber(value: total)) ?? "\(total)"
            let activeBuckets = data.filter { $0.count > 0 }.count
            return "Total \(formatted) \(unit.displayName) over \(activeBuckets) \(bucketLabel)"
        case .count:
            let total = data.reduce(0) { $0 + $1.count }
            let activeBuckets = data.filter { $0.count > 0 }.count
            return "\(total) logs over \(activeBuckets) \(bucketLabel)"
        }
    }

    // Sheet data providers run once at presentation, so they filter the raw
    // queries directly instead of keeping a filtered copy alive per render.
    private func entriesForDay(_ date: Date) -> [SetEntry] {
        let calendar = Calendar.current
        return entries.filter { entry in
            guard selectedExerciseID == nil || entry.exercise.id == selectedExerciseID else { return false }
            return calendar.isDate(entry.performedAt, inSameDayAs: date)
        }
    }

    private func entriesForWeek(weekStart: Date) -> [SetEntry] {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return entries.filter { entry in
            guard selectedExerciseID == nil || entry.exercise.id == selectedExerciseID else { return false }
            return entry.performedAt >= weekStart && entry.performedAt < weekEnd
        }
    }

    private func supplementEntriesForDay(_ date: Date) -> [SupplementEntry] {
        let calendar = Calendar.current
        return supplementEntries.filter { entry in
            guard selectedSupplementTypeID == nil || entry.type.id == selectedSupplementTypeID else { return false }
            return calendar.isDate(entry.takenAt, inSameDayAs: date)
        }
    }

    private func supplementEntriesForWeek(weekStart: Date) -> [SupplementEntry] {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return supplementEntries.filter { entry in
            guard selectedSupplementTypeID == nil || entry.type.id == selectedSupplementTypeID else { return false }
            return entry.takenAt >= weekStart && entry.takenAt < weekEnd
        }
    }

    private func setsLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    private func paddedDateDomain(
        _ range: ClosedRange<Date>?,
        component: Calendar.Component,
        value: Int
    ) -> ClosedRange<Date>? {
        guard let range else { return nil }
        let calendar = Calendar.current
        let lowerBound = calendar.date(byAdding: component, value: -value, to: range.lowerBound) ?? range.lowerBound
        let upperBound = calendar.date(byAdding: component, value: value, to: range.upperBound) ?? range.upperBound
        return lowerBound ... upperBound
    }

    private func paddedNumericDomain(maxValue: Double) -> ClosedRange<Double> {
        let upperValue = max(maxValue, 1)
        let padding = max(1, upperValue * 0.12)
        return 0 ... (upperValue + padding)
    }

    private func selectDay(_ date: Date) {
        selectedWeekStart = nil
        selectedSupplementDay = nil
        selectedDay = date
    }

    private func selectWeekStart(_ date: Date) {
        selectedDay = nil
        selectedSupplementDay = nil
        selectedWeekStart = date
    }

    private func selectSupplementDay(_ date: Date, derived: TrendsDerivedData) {
        let selectedDate = nearestSupplementDay(to: date, in: derived.supplementSummariesWithLogs) ?? date
        selectedDay = nil
        selectedWeekStart = nil
        selectedSupplementDay = selectedDate
        if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit {
            openSupplementDrilldown(for: selectedDate)
        }
    }

    private func clearSelections() {
        selectedDay = nil
        selectedWeekStart = nil
        selectedSupplementDay = nil
        sheetDestination = nil
    }

    private func prCardsAccessibilityLabel(
        bestWeightEntry: SetEntry?,
        bestDistanceEntry: SetEntry?,
        fastestSpeedEntry: SetEntry?,
        bestReps: Int?,
        bestDuration: Int?,
        sessionCount: Int
    ) -> String {
        let weightText: String
        if let entry = bestWeightEntry {
            let formatted = Formatters.weight.string(from: NSNumber(value: entry.weight ?? 0)) ?? "\(entry.weight ?? 0)"
            weightText = "Best weight \(formatted) \(entry.weightUnit.symbol)"
        } else {
            weightText = "Best weight none"
        }

        let distanceText: String
        if let entry = bestDistanceEntry, let distance = entry.distance {
            distanceText = "Best distance \(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))"
        } else {
            distanceText = "Best distance none"
        }

        let speedText: String
        if let entry = fastestSpeedEntry,
           let distance = entry.distance,
           let durationSeconds = entry.durationSeconds,
           durationSeconds > 0,
           let pace = Formatters.paceText(distance: distance, unit: entry.distanceUnit, durationSeconds: durationSeconds) {
            speedText = "Fastest pace \(pace)"
        } else {
            speedText = "Fastest pace none"
        }

        let repsText = bestReps.map { "Best reps \($0)" } ?? "Best reps none"
        let durationText = bestDuration.map { "Longest duration \(DateHelper.formattedDuration(seconds: $0))" } ?? "Longest duration none"
        let sessionsText = "Sessions \(sessionCount)"
        let primaryParts = bestDistanceEntry != nil
            ? [distanceText, speedText, durationText, sessionsText]
            : [weightText, repsText, durationText, sessionsText]
        return primaryParts.joined(separator: ", ")
    }
}

private extension View {
    @ViewBuilder
    func chartDateDomain(_ domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain)
        } else {
            self
        }
    }
}

private struct TrendSummaryItem: Identifiable {
    let title: String
    let value: String
    let detail: String
    var accent: Color? = nil

    var id: String { title }
}

private struct PRCardMetric {
    let title: String
    let value: String
}

struct TrendsExerciseSearchView: View {
    let exercises: [Exercise]
    let entries: [SetEntry]
    @Binding var selectedExerciseID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                allExercisesRow
            }

            if trimmedSearchText.isEmpty, !recentExercises.isEmpty {
                Section {
                    ForEach(recentExercises) { exercise in
                        exerciseRow(for: exercise)
                    }
                } header: {
                    SectionHeaderView(title: "Recent")
                }
            }

            if filteredExercises.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Text("No exercises match that search.")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text("Clear the search or choose All Exercises to see the full trend view.")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xs)
                    .marbleRowInsets()
                    .accessibilityIdentifier("Trends.ExerciseSearch.EmptyState")
                }
            } else {
                ForEach(ExerciseCategory.allCases) { category in
                    let categoryExercises = filteredExercises.filter { $0.category == category }
                    if !categoryExercises.isEmpty {
                        Section {
                            ForEach(categoryExercises) { exercise in
                                exerciseRow(for: exercise)
                            }
                        } header: {
                            SectionHeaderView(title: category.displayName)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Trends.ExerciseSearch.List")
        .navigationTitle("Filter Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .accessibilityIdentifier("Trends.ExerciseSearch.Done")
            }
        }
    }

    private var allExercisesRow: some View {
        Button {
            selectedExerciseID = nil
            dismiss()
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
                ScaledSymbol(systemName: "line.3.horizontal.decrease.circle", size: 18, weight: .semibold, frameSize: MarbleLayout.rowIconSize)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text("All Exercises")
                        .font(MarbleTypography.rowTitle)
                    Text("Show every logged set in Trends.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if selectedExerciseID == nil {
                    Image(systemName: "checkmark")
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .accessibilityIdentifier("Trends.ExerciseSearch.All")
        .accessibilityValue(selectedExerciseID == nil ? "Selected" : "Not selected")
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExercises: [Exercise] {
        if trimmedSearchText.isEmpty {
            return exercises
        }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var recentExercises: [Exercise] {
        var seen = Set<UUID>()
        var unique: [Exercise] = []
        let availableIDs = Set(exercises.map(\.id))

        for entry in entries {
            let exercise = entry.exercise
            guard availableIDs.contains(exercise.id), !seen.contains(exercise.id) else { continue }
            seen.insert(exercise.id)
            unique.append(exercise)
            if unique.count >= 5 {
                break
            }
        }

        return unique
    }

    private func exerciseRow(for exercise: Exercise) -> some View {
        let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
        return Button {
            selectedExerciseID = exercise.id
            dismiss()
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
                ExerciseIconView(exercise: exercise, fontSize: 18, frameSize: MarbleLayout.rowIconSize)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    HStack(spacing: MarbleSpacing.xs) {
                        Text(exercise.name)
                            .font(MarbleTypography.rowTitle)

                        if exercise.isFavorite {
                            Image(systemName: "star.fill")
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .accessibilityHidden(true)
                        }
                    }

                    Text(exercise.configurationSummaryText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if selectedExerciseID == exercise.id {
                    Image(systemName: "checkmark")
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .accessibilityIdentifier("Trends.ExerciseSearch.Row.\(sanitizedName)")
        .accessibilityValue(exercise.configurationSummaryText)
    }
}

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

private struct TrendSummaryItemView: View {
    let item: TrendSummaryItem

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            HStack(spacing: MarbleSpacing.xxs) {
                if let accent = item.accent {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(item.title)
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .textCase(.uppercase)
            }

            Text(item.value)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.detail)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.value), \(item.detail)")
    }
}

struct VolumeDatum: Identifiable {
    let weekStart: Date
    let series: VolumeSeries
    let value: Double

    var id: String { "\(weekStart.timeIntervalSince1970)-\(series.rawValue)" }
}

enum VolumeSeries: String, CaseIterable {
    case weighted
    case reps
    case duration

    var label: String {
        switch self {
        case .weighted:
            return "Weight x Reps"
        case .reps:
            return "Bodyweight Reps"
        case .duration:
            return "Duration (min)"
        }
    }

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .weighted:
            return TrendsPalette.volumeWeighted.color(for: scheme)
        case .reps:
            return TrendsPalette.volumeReps.color(for: scheme)
        case .duration:
            return TrendsPalette.volumeDuration.color(for: scheme)
        }
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sevenDays:
            return "7D"
        case .thirtyDays:
            return "30D"
        case .ninetyDays:
            return "90D"
        case .oneYear:
            return "1Y"
        case .all:
            return "All"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: AppEnvironment.now))
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: AppEnvironment.now))
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: AppEnvironment.now))
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: AppEnvironment.now))
        case .all:
            return nil
        }
    }
}
