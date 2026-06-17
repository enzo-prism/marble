import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        trendsRoot
            .sheet(item: $sheetDestination) { destination in
                detailsSheet(for: destination)
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
                    sheetDestination = .day(day)
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
                    sheetDestination = .supplementDay(day)
                }
            }
    }

    private var trendsRoot: some View {
        NavigationStack {
            trendsScroll
        }
    }

    private var trendsScroll: some View {
        ScrollView {
            trendsContent
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
        .navigationSubtitleWhenAvailable(selectedExerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                exerciseSearchButton
                AddSetToolbarButton()
            }
        }
    }

    private var trendsContent: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.l) {
            rangePicker
            if hasAnyTrendData {
                periodInsightHeader
            }

            if !hasAnyTrendData {
                EmptyStateView(
                    title: "No trend data yet",
                    message: "Log sets or supplements to see trends.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .accessibilityIdentifier("Trends.EmptyState")
            } else {
                workoutTrendSections
                secondaryAndSupplementSections
                prSection
            }
        }
        .padding(MarbleLayout.pagePadding)
    }

    @ViewBuilder
    private var workoutTrendSections: some View {
        if hasFilteredSetData {
            consistencySection

            if selectedExercise != nil {
                progressSection
            }

            weeklyVolumeSection
        } else {
            Text("No workout data for this range.")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private var secondaryAndSupplementSections: some View {
        if hasSecondaryHighlights {
            secondaryHighlightsSection
                .padding(.top, MarbleSpacing.l)
        }

        supplementsSection
            .padding(.top, MarbleSpacing.xxl)
    }

    @ViewBuilder
    private var prSection: some View {
        if hasFilteredSetData {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text("PRs")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                prCards
            }
        }
    }

    @ViewBuilder
    private func detailsSheet(for destination: TrendsSheetDestination) -> some View {
        switch destination {
        case .day(let date):
            DayDetailsSheet(date: date, entries: entriesForDay(date))
        case .week(let weekStart):
            let weekEnd = TrendsDateHelper.endOfWeek(for: weekStart)
            WeekDetailsSheet(weekStart: weekStart, weekEnd: weekEnd, entries: entriesForWeek(weekStart: weekStart))
        case .supplementDay(let date):
            SupplementDayDetailsSheet(date: date, entries: supplementEntriesForDay(date))
        }
    }

    private var hasFilteredSetData: Bool {
        !filteredEntries.isEmpty
    }

    private var hasFilteredSupplementData: Bool {
        !filteredSupplementEntries.isEmpty
    }

    private var hasAnyTrendData: Bool {
        hasFilteredSetData || hasFilteredSupplementData
    }

    private var filteredEntries: [SetEntry] {
        var filtered = entries
        if let selectedExerciseID {
            filtered = filtered.filter { $0.exercise.id == selectedExerciseID }
        }
        if let startDate = range.startDate {
            filtered = filtered.filter { $0.performedAt >= startDate }
        }
        return filtered
    }

    private var filteredSupplementEntries: [SupplementEntry] {
        var filtered = supplementEntries
        if let selectedSupplementTypeID {
            filtered = filtered.filter { $0.type.id == selectedSupplementTypeID }
        }
        if let startDate = range.startDate {
            filtered = filtered.filter { $0.takenAt >= startDate }
        }
        return filtered
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

    private var periodInsightHeader: some View {
        let insight = periodInsight
        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("This period")
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)

            Text(insight.title)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = insight.detail, !dynamicTypeSize.isAccessibilitySize {
                Text(detail)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Trends.PeriodInsight")
    }

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Consistency")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
            consistencyChart
            if let consistencyCaptionText {
                insightCaption(consistencyCaptionText, identifier: "Trends.ConsistencyCaption")
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Progress")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
            if progressPoints.isEmpty {
                Text("No progress yet")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            } else {
                if let selectedExercise {
                    ExerciseHeadlineView(
                        points: progressPoints,
                        metricInfo: ExerciseProgressBuilder.metricInfo(for: selectedExercise)
                    )
                }
                ExerciseProgressChart(points: progressPoints, isScrubbing: $isScrubbingChart) { date in
                    sheetDestination = .day(date)
                }
            }
        }
        .accessibilityIdentifier("Trends.ProgressSection")
    }

    private var weeklyVolumeSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Weekly Volume")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
            volumeChart
            if let volumeCaptionText {
                insightCaption(volumeCaptionText, identifier: "Trends.VolumeCaption")
            }
        }
    }

    private var secondaryHighlightsSection: some View {
        let momentumSummary = momentum
        return VStack(alignment: .leading, spacing: MarbleSpacing.l) {
            if momentumSummary.hasContent {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    Text("Momentum")
                        .font(MarbleTypography.sectionTitle)
                        .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                    MomentumStripView(summary: momentumSummary)
                }
                .accessibilityIdentifier("Trends.MomentumSection")
            }

            if let selectedLiftBests {
                LiftBestsHighlightView(bests: selectedLiftBests)
            }

            if !trendSummaryItems.isEmpty {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    Text("Summary")
                        .font(MarbleTypography.sectionTitle)
                        .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    trendSummaryStrip
                }
                .accessibilityIdentifier("Trends.SummarySection")
            }
        }
        .accessibilityIdentifier("Trends.Highlights")
    }

    private var hasSecondaryHighlights: Bool {
        momentum.hasContent || selectedLiftBests != nil || !trendSummaryItems.isEmpty
    }

    private var exerciseSearchButton: some View {
        Button {
            isPresentingExerciseSearch = true
        } label: {
            Image(systemName: selectedExercise == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 17, weight: .semibold))
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

    private var periodInsight: TrendPeriodInsight {
        let setCount = filteredEntries.count
        let activeDays = Set(filteredEntries.map { Calendar.current.startOfDay(for: $0.performedAt) }).count
        let supplementLogs = filteredSupplementEntries.count
        let title: String
        var details: [String] = []

        if setCount > 0 {
            let dayWord = activeDays == 1 ? "day" : "days"
            title = "\(setsLabel(for: setCount)) across \(activeDays) active \(dayWord)"
            if let selectedExercise {
                details.append(selectedExercise.name)
            }
            if let bestWeek = bestWeekSummary {
                details.append("Best week \(TrendsDateHelper.weekLabel(start: bestWeek.weekStart, end: bestWeek.weekEnd)) · \(setsLabel(for: bestWeek.setCount))")
            }
            if supplementLogs > 0 {
                details.append(supplementLogs == 1 ? "1 supplement log" : "\(supplementLogs) supplement logs")
            }
        } else {
            title = supplementLogs == 1 ? "1 supplement log" : "\(supplementLogs) supplement logs"
            details.append(selectedSupplementType?.name ?? "All supplements")
        }

        let detail = details.isEmpty ? nil : details.prefix(2).joined(separator: " · ")
        return TrendPeriodInsight(title: title, detail: detail)
    }

    private var trendSummaryStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MarbleSpacing.xs) {
                ForEach(trendSummaryItems) { item in
                    TrendSummaryItemView(item: item)
                }
            }

            VStack(spacing: MarbleSpacing.xs) {
                ForEach(trendSummaryItems) { item in
                    TrendSummaryItemView(item: item)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Trends.Summary")
    }

    private var trendSummaryItems: [TrendSummaryItem] {
        let activeDays = Set(filteredEntries.map { Calendar.current.startOfDay(for: $0.performedAt) }).count
        let supplementLogs = filteredSupplementEntries.count
        var items: [TrendSummaryItem] = []
        if !filteredEntries.isEmpty {
            let dayWord = activeDays == 1 ? "day" : "days"
            items.append(TrendSummaryItem(title: "Sets", value: "\(filteredEntries.count)", detail: "\(activeDays) active \(dayWord)"))
            items.append(TrendSummaryItem(title: "Best Week", value: bestWeekSummary.map { "\($0.setCount)" } ?? "-", detail: bestWeekSummary.map { TrendsDateHelper.weekLabel(start: $0.weekStart, end: $0.weekEnd) } ?? "No week yet"))
        }
        if supplementLogs > 0 {
            items.append(TrendSummaryItem(title: "Supplements", value: "\(supplementLogs)", detail: selectedSupplementType?.name ?? "All types"))
        }
        return items
    }

    private var bestWeekSummary: TrendWeeklySummary? {
        weeklySummaries.max { $0.setCount < $1.setCount }
    }

    private var consistencyChart: some View {
        let summaries = dailySummaries
        let selectedSummary = selectedDailySummary
        let tooltipSummary = selectedSummary
        let prSummary = dailyPRSummary
        let yDomain = paddedNumericDomain(maxValue: Double(max(dailyPRCount, 1)))
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.date,
                  let end = summaries.last?.date else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: 1)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(summaries) { item in
                    LineMark(
                        x: .value("Day", item.date),
                        y: .value("Sets", item.count)
                    )
                    .foregroundStyle(Theme.dividerColor(for: colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityHidden(true)
                }

                if let prSummary, prSummary.count > 0 {
                    PointMark(
                        x: .value("PR Day", prSummary.date),
                        y: .value("Sets", prSummary.count)
                    )
                    .symbol {
                        Circle()
                            .stroke(Theme.secondaryTextColor(for: colorScheme), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    }
                    .symbolSize(28)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Day", selectedSummary.date))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                    PointMark(
                        x: .value("Selected Day", selectedSummary.date),
                        y: .value("Sets", selectedSummary.count)
                    )
                    .symbolSize(70)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
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
                    title: DateHelper.dayLabel(for: tooltipSummary.date),
                    valueText: setsLabel(for: tooltipSummary.count),
                    summaryText: tooltipSummary.summaryText,
                    showsPR: tooltipSummary.count == dailyPRCount && dailyPRCount > 0,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for \(DateHelper.dayLabel(for: tooltipSummary.date))",
                    viewSetsIdentifier: "Trends.ConsistencyTooltip.ViewSets",
                    onViewSets: {
                        sheetDestination = .day(tooltipSummary.date)
                    },
                    onClear: {
                        selectedDay = nil
                    }
                )
                .accessibilityIdentifier("Trends.ConsistencyTooltip")
            }
        }
    }

    private var volumeChart: some View {
        let data = volumeData
        let summaries = weeklySummaries
        let selectedSummary = selectedWeeklySummary
        let tooltipSummary = selectedSummary
        let prSummary = weeklyPRSummary
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.weekStart,
                  let end = summaries.last?.weekStart else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: 4)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Week", item.weekStart),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(item.series.color(for: colorScheme))
                    .position(by: .value("Series", item.series.label))
                    .accessibilityHidden(true)
                }

                if let prSummary, prSummary.totalVolumeScore > 0 {
                    PointMark(
                        x: .value("PR Week", prSummary.weekStart),
                        y: .value("Value", prSummary.maxSeriesValue)
                    )
                    .symbol {
                        Circle()
                            .stroke(Theme.secondaryTextColor(for: colorScheme), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    }
                    .symbolSize(28)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Week", selectedSummary.weekStart))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                    PointMark(
                        x: .value("Selected Week", selectedSummary.weekStart),
                        y: .value("Value", selectedSummary.maxSeriesValue)
                    )
                    .symbolSize(70)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
            .chartLegend(position: .bottom, alignment: .leading)
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

            if let tooltipSummary {
                let label = TrendsDateHelper.weekLabel(start: tooltipSummary.weekStart, end: tooltipSummary.weekEnd)
                TrendTooltipView(
                    title: label,
                    valueText: tooltipSummary.valueText,
                    summaryText: tooltipSummary.summaryText,
                    showsPR: tooltipSummary.totalVolumeScore == weeklyPRTotal && weeklyPRTotal > 0,
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

    private var supplementsSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Supplements")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Spacer(minLength: MarbleSpacing.s)

                supplementPicker
            }

            if filteredSupplementEntries.isEmpty {
                Text("No supplement data yet")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.SupplementsEmpty")
            } else {
                supplementsChart
            }
        }
    }

    private var supplementsChart: some View {
        let summaries = supplementDailySummaries
        let selectedSummary = selectedSupplementSummary
        let yDomain = paddedNumericDomain(maxValue: summaries.map(\.chartValue).max() ?? 1)
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.date,
                  let end = summaries.last?.date else {
                return nil
            }
            return start ... end
        }()
        let chartDomain = paddedDateDomain(dataRange, component: .day, value: 1)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Chart {
                ForEach(summaries) { item in
                    LineMark(
                        x: .value("Day", item.date),
                        y: .value("Value", item.chartValue)
                    )
                    .foregroundStyle(Theme.dividerColor(for: colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityHidden(true)
                }

                if let selectedSummary {
                    RuleMark(x: .value("Selected Day", selectedSummary.date))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                    PointMark(
                        x: .value("Selected Day", selectedSummary.date),
                        y: .value("Value", selectedSummary.chartValue)
                    )
                    .symbolSize(70)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
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
                            accessibilityValue: supplementAccessibilityValue(for: summaries),
                            isScrubbing: $isScrubbingChart
                        ) { date in
                            selectSupplementDay(date)
                        }
                        .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }

            if let selectedSummary {
                let label = DateHelper.dayLabel(for: selectedSummary.date)
                TrendTooltipView(
                    title: label,
                    valueText: selectedSummary.valueText,
                    summaryText: selectedSummary.summaryText,
                    showsPR: false,
                    viewSetsLabel: "View logs",
                    viewSetsAccessibilityLabel: "View supplement logs for \(label)",
                    viewSetsIdentifier: "Trends.SupplementsTooltip.ViewLogs",
                    onViewSets: {
                        sheetDestination = .supplementDay(selectedSummary.date)
                    },
                    onClear: {
                        selectedSupplementDay = nil
                    }
                )
                .accessibilityIdentifier("Trends.SupplementsTooltip")
            }
        }
    }

    private var prCards: some View {
        let bestWeightEntry = filteredEntries
            .filter { $0.weight != nil }
            .max { (lhs, rhs) in
                (lhs.weight ?? 0) < (rhs.weight ?? 0)
            }
        let bestDistanceEntry = filteredEntries
            .filter { $0.distance != nil }
            .max { (lhs, rhs) in
                (lhs.distance ?? 0) < (rhs.distance ?? 0)
            }
        let fastestSpeedEntry = filteredEntries
            .filter { ($0.distance ?? 0) > 0 && ($0.durationSeconds ?? 0) > 0 }
            .max { lhs, rhs in
                let lhsSpeed = (lhs.distance ?? 0) / Double(max(lhs.durationSeconds ?? 1, 1))
                let rhsSpeed = (rhs.distance ?? 0) / Double(max(rhs.durationSeconds ?? 1, 1))
                return lhsSpeed < rhsSpeed
            }
        let bestReps = filteredEntries.compactMap { $0.reps }.max()
        let bestDuration = filteredEntries.compactMap { $0.durationSeconds }.max()
        let sessionCount = Set(filteredEntries.map { DateHelper.startOfDay(for: $0.performedAt) }).count
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
                ? fastestSpeedEntry.map { fastestEntry in
                    let speed = (fastestEntry.distance ?? 0) / Double(max(fastestEntry.durationSeconds ?? 1, 1))
                    let formatted = Formatters.distance.string(from: NSNumber(value: speed)) ?? "\(speed)"
                    return "\(formatted) \(fastestEntry.distanceUnit.symbol)/s"
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

    private var dailySummaries: [TrendDailySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.performedAt)
        }

        if range == .all {
            return grouped.keys.sorted().map { day in
                TrendDailySummary(date: day, entries: grouped[day] ?? [])
            }
        }

        guard let startDate = range.startDate else { return [] }
        let endDate = calendar.startOfDay(for: AppEnvironment.now)
        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates.map { day in
            TrendDailySummary(date: day, entries: grouped[day] ?? [])
        }
    }

    private var dailySummaryLookup: [Date: TrendDailySummary] {
        Dictionary(uniqueKeysWithValues: dailySummaries.map { ($0.date, $0) })
    }

    private var selectedDailySummary: TrendDailySummary? {
        guard let selectedDay else { return nil }
        guard let nearest = nearestDay(to: selectedDay, in: dailySummaries) else { return nil }
        return dailySummaryLookup[nearest]
    }

    private var dailyPRCount: Int {
        dailySummaries.map(\.count).max() ?? 0
    }

    private var dailyPRSummary: TrendDailySummary? {
        guard dailyPRCount > 0 else { return nil }
        return dailySummaries.filter { $0.count == dailyPRCount }.max(by: { $0.date < $1.date })
    }

    private var weeklySummaries: [TrendWeeklySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            TrendsDateHelper.startOfWeek(for: entry.performedAt, calendar: calendar)
        }

        var summaries: [TrendWeeklySummary] = []
        for (weekStart, items) in grouped {
            var weightedVolume: Double = 0
            var repsVolume: Int = 0
            var durationSeconds: Int = 0

            for item in items {
                if let weight = item.weight, let reps = item.reps {
                    weightedVolume += weight * Double(reps)
                } else if let reps = item.reps {
                    repsVolume += reps
                }
                if let duration = item.durationSeconds {
                    durationSeconds += duration
                }
            }

            let durationMinutes = Double(durationSeconds) / 60.0
            let maxSeriesValue = max(weightedVolume, Double(repsVolume), durationMinutes)
            let weekEnd = TrendsDateHelper.endOfWeek(for: weekStart, calendar: calendar)
            summaries.append(TrendWeeklySummary(
                weekStart: weekStart,
                weekEnd: weekEnd,
                entries: items,
                weightedVolume: weightedVolume,
                repsVolume: repsVolume,
                durationMinutes: durationMinutes,
                maxSeriesValue: maxSeriesValue
            ))
        }

        return summaries.sorted { $0.weekStart < $1.weekStart }
    }

    private var weeklySummaryLookup: [Date: TrendWeeklySummary] {
        Dictionary(uniqueKeysWithValues: weeklySummaries.map { ($0.weekStart, $0) })
    }

    private var selectedWeeklySummary: TrendWeeklySummary? {
        guard let selectedWeekStart else { return nil }
        guard let nearest = nearestWeekStart(to: selectedWeekStart, in: weeklySummaries) else { return nil }
        return weeklySummaryLookup[nearest]
    }

    private var weeklyPRTotal: Double {
        weeklySummaries.map(\.totalVolumeScore).max() ?? 0
    }

    private var weeklyPRSummary: TrendWeeklySummary? {
        guard weeklyPRTotal > 0 else { return nil }
        return weeklySummaries
            .filter { $0.totalVolumeScore == weeklyPRTotal }
            .max(by: { $0.weekStart < $1.weekStart })
    }

    private var supplementDisplayMode: SupplementTrendDisplayMode {
        guard let selectedType = selectedSupplementType else {
            return .count(reason: .allSupplements)
        }

        let entries = filteredSupplementEntries
        let unitsWithDose = Set(entries.compactMap { entry in
            entry.dose == nil ? nil : entry.unit
        })
        if unitsWithDose.count > 1 {
            return .count(reason: .mixedUnits)
        }
        if unitsWithDose.isEmpty {
            return .count(reason: .noDoseData)
        }
        return .dose(unit: unitsWithDose.first ?? selectedType.unit)
    }

    private var supplementDailySummaries: [SupplementDailySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSupplementEntries) { entry in
            calendar.startOfDay(for: entry.takenAt)
        }

        if range == .all {
            return grouped.keys.sorted().map { day in
                SupplementDailySummary(
                    date: day,
                    entries: grouped[day] ?? [],
                    mode: supplementDisplayMode
                )
            }
        }

        guard let startDate = range.startDate else { return [] }
        let endDate = calendar.startOfDay(for: AppEnvironment.now)
        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates.map { day in
            SupplementDailySummary(
                date: day,
                entries: grouped[day] ?? [],
                mode: supplementDisplayMode
            )
        }
    }

    private var supplementDailySummaryLookup: [Date: SupplementDailySummary] {
        Dictionary(uniqueKeysWithValues: supplementDailySummaries.map { ($0.date, $0) })
    }

    private var selectedSupplementSummary: SupplementDailySummary? {
        guard let selectedSupplementDay else { return nil }
        guard let nearest = nearestSupplementDay(to: selectedSupplementDay, in: supplementDailySummaries) else { return nil }
        return supplementDailySummaryLookup[nearest]
    }

    private var supplementSummariesWithLogs: [SupplementDailySummary] {
        supplementDailySummaries.filter { $0.count > 0 }
    }

    private var volumeData: [VolumeDatum] {
        var data: [VolumeDatum] = []
        for summary in weeklySummaries {
            if summary.weightedVolume > 0 {
                data.append(VolumeDatum(weekStart: summary.weekStart, series: .weighted, value: summary.weightedVolume))
            }
            if summary.repsVolume > 0 {
                data.append(VolumeDatum(weekStart: summary.weekStart, series: .reps, value: Double(summary.repsVolume)))
            }
            if summary.durationMinutes > 0 {
                data.append(VolumeDatum(weekStart: summary.weekStart, series: .duration, value: summary.durationMinutes))
            }
        }
        return data.sorted { $0.weekStart < $1.weekStart }
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
        let activeDays = data.filter { $0.count > 0 }.count
        return "\(totalSets) sets over \(activeDays) active days"
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

    private func supplementAccessibilityValue(for data: [SupplementDailySummary]) -> String {
        guard !data.isEmpty else { return "No data" }
        switch supplementDisplayMode {
        case .dose(let unit):
            let total = data.reduce(0.0) { $0 + $1.totalDose }
            let formatted = Formatters.dose.string(from: NSNumber(value: total)) ?? "\(total)"
            let activeDays = data.filter { $0.count > 0 }.count
            return "Total \(formatted) \(unit.displayName) over \(activeDays) days"
        case .count:
            let total = data.reduce(0) { $0 + $1.count }
            let activeDays = data.filter { $0.count > 0 }.count
            return "\(total) logs over \(activeDays) days"
        }
    }

    private func entriesForDay(_ date: Date) -> [SetEntry] {
        let target = Calendar.current.startOfDay(for: date)
        return filteredEntries.filter { Calendar.current.isDate($0.performedAt, inSameDayAs: target) }
    }

    private func entriesForWeek(weekStart: Date) -> [SetEntry] {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return filteredEntries.filter { entry in
            entry.performedAt >= weekStart && entry.performedAt < weekEnd
        }
    }

    private func supplementEntriesForDay(_ date: Date) -> [SupplementEntry] {
        let target = Calendar.current.startOfDay(for: date)
        return filteredSupplementEntries.filter { Calendar.current.isDate($0.takenAt, inSameDayAs: target) }
    }

    private var progressPoints: [ExerciseProgressPoint] {
        guard let selectedExercise else { return [] }
        return ExerciseProgressBuilder.buildPoints(entries: entries, exercise: selectedExercise, range: range)
    }

    private var selectedLiftBests: ExerciseLiftBests? {
        guard let selectedExercise else { return nil }
        return ExerciseProgressBuilder.buildLiftBests(entries: entries, exercise: selectedExercise, range: range)
    }

    /// Entries scoped to the selected exercise (if any) but not filtered by range, so momentum
    /// can compare the current window to the previous one and detect all-time records.
    private var exerciseScopedEntries: [SetEntry] {
        guard let selectedExerciseID else { return entries }
        return entries.filter { $0.exercise.id == selectedExerciseID }
    }

    private var momentum: MomentumSummary {
        MomentumBuilder.build(entries: exerciseScopedEntries, range: range, exercise: selectedExercise)
    }

    private var consistencyCaptionText: String? {
        let summaries = dailySummaries
        let activeDays = summaries.filter { $0.count > 0 }.count
        guard activeDays > 0 else { return nil }
        let totalSets = summaries.reduce(0) { $0 + $1.count }
        let dayWord = activeDays == 1 ? "day" : "days"
        if let prSummary = dailyPRSummary, dailyPRCount > 0 {
            return "Most active \(DateHelper.dayLabel(for: prSummary.date)) · \(setsLabel(for: prSummary.count)). \(totalSets) sets across \(activeDays) active \(dayWord)."
        }
        return "\(totalSets) sets across \(activeDays) active \(dayWord)."
    }

    private var volumeCaptionText: String? {
        guard let best = weeklySummaries.max(by: { $0.totalVolumeScore < $1.totalVolumeScore }),
              best.totalVolumeScore > 0 else {
            return nil
        }
        let label = TrendsDateHelper.weekLabel(start: best.weekStart, end: best.weekEnd)
        return "Best week \(label) · \(best.valueText)."
    }

    @ViewBuilder
    private func insightCaption(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(MarbleTypography.rowMeta)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
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

    private func selectSupplementDay(_ date: Date) {
        let selectedDate = nearestSupplementDay(to: date, in: supplementSummariesWithLogs) ?? date
        selectedDay = nil
        selectedWeekStart = nil
        selectedSupplementDay = selectedDate
        if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit {
            sheetDestination = .supplementDay(selectedDate)
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
           durationSeconds > 0 {
            let speed = distance / Double(durationSeconds)
            let formatted = Formatters.distance.string(from: NSNumber(value: speed)) ?? "\(speed)"
            speedText = "Fastest pace \(formatted) \(entry.distanceUnit.symbol) per second"
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

    var id: String { title }
}

private struct TrendPeriodInsight {
    let title: String
    let detail: String?
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
        .minimizeSearchToolbarWhenAvailable()
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
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
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
            Text(item.title)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)

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
        // A wide dark→light ramp off the primary ink keeps the three series distinguishable
        // (the previous near-identical greys were hard to tell apart) while staying monochrome.
        let base = Theme.primaryTextColor(for: scheme)
        switch self {
        case .weighted:
            return base.opacity(0.85)
        case .reps:
            return base.opacity(0.55)
        case .duration:
            return base.opacity(0.28)
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

    /// Length of the range in days, or `nil` for `.all` (which has no fixed window).
    var dayCount: Int? {
        switch self {
        case .sevenDays:
            return 7
        case .thirtyDays:
            return 30
        case .ninetyDays:
            return 90
        case .oneYear:
            return 365
        case .all:
            return nil
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
