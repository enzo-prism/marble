import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var range: TrendRange = .thirtyDays
    @State private var selectedExercise: Exercise?
    @State private var selectedDay: Date?
    @State private var selectedWeekStart: Date?
    @State private var sheetDestination: TrendsSheetDestination?
    @State private var isScrubbingChart = false

    init(
        initialRange: TrendRange = .thirtyDays,
        initialExercise: Exercise? = nil,
        initialSelectedDay: Date? = nil,
        initialSelectedWeekStart: Date? = nil
    ) {
        _range = State(initialValue: initialRange)
        _selectedExercise = State(initialValue: initialExercise)
        _selectedDay = State(initialValue: initialSelectedDay)
        _selectedWeekStart = State(initialValue: initialSelectedWeekStart)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    rangePicker
                    exercisePicker

                    if filteredEntries.isEmpty {
                        EmptyStateView(title: "No trend data yet", message: "Log sets to see consistency and PRs.", systemImage: "chart.line.uptrend.xyaxis")
                            .accessibilityIdentifier("Trends.EmptyState")
                    } else {
                        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                            Text("Consistency")
                                .font(MarbleTypography.sectionTitle)
                                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                            consistencyChart
                        }

                        if let selectedExercise {
                            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                Text("Progress")
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                if progressPoints.isEmpty {
                                    Text("No progress yet")
                                        .font(MarbleTypography.rowMeta)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                } else {
                                    ExerciseProgressChart(points: progressPoints, isScrubbing: $isScrubbingChart) { date in
                                        sheetDestination = .day(date)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                            Text("Weekly Volume")
                                .font(MarbleTypography.sectionTitle)
                                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                            volumeChart
                        }

                        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                            Text("PRs")
                                .font(MarbleTypography.sectionTitle)
                                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                .accessibilityHidden(true)
                            prCards
                        }
                    }
                }
                .padding(MarbleLayout.pagePadding)
            }
            .scrollDisabled(isScrubbingChart)
            .accessibilityIdentifier("Trends.Scroll")
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
        }
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .day(let date):
                DayDetailsSheet(date: date, entries: entriesForDay(date))
            case .week(let weekStart):
                let weekEnd = TrendsDateHelper.endOfWeek(for: weekStart)
                WeekDetailsSheet(weekStart: weekStart, weekEnd: weekEnd, entries: entriesForWeek(weekStart: weekStart))
            }
        }
        .onChange(of: range) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedExercise) { _, _ in
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
    }

    private var filteredEntries: [SetEntry] {
        var filtered = entries
        if let selectedExercise {
            filtered = filtered.filter { $0.exercise == selectedExercise }
        }
        if let startDate = range.startDate {
            filtered = filtered.filter { $0.performedAt >= startDate }
        }
        return filtered
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(Theme.dividerColor(for: colorScheme))
        .accessibilityIdentifier("Trends.Range")
    }

    private var exercisePicker: some View {
        Picker("Exercise", selection: $selectedExercise) {
            Text("All Exercises").tag(Exercise?.none)
            ForEach(exercises) { exercise in
                Text(exercise.name).tag(exercise as Exercise?)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("Trends.ExerciseFilter")
        .accessibilityValue(selectedExercise?.name ?? "All Exercises")
    }

    private var consistencyChart: some View {
        let summaries = dailySummaries
        let selectedSummary = selectedDailySummary
        let tooltipSummary = selectedSummary
        let prSummary = dailyPRSummary
        let dataRange: ClosedRange<Date>? = {
            guard let start = summaries.first?.date,
                  let end = summaries.last?.date else {
                return nil
            }
            return start ... end
        }()

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
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                    }
                    .symbolSize(40)
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
            .frame(height: 180)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotFrame = proxy.plotFrame.map { geometry[$0] } ?? geometry[proxy.plotAreaFrame]
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
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                    }
                    .symbolSize(40)
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
            .frame(height: 180)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotFrame = proxy.plotFrame.map { geometry[$0] } ?? geometry[proxy.plotAreaFrame]
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

    private var prCards: some View {
        let bestWeightEntry = filteredEntries
            .filter { $0.weight != nil }
            .max { (lhs, rhs) in
                (lhs.weight ?? 0) < (rhs.weight ?? 0)
            }
        let bestReps = filteredEntries.compactMap { $0.reps }.max()
        let bestDuration = filteredEntries.compactMap { $0.durationSeconds }.max()
        let sessionCount = Set(filteredEntries.map { DateHelper.startOfDay(for: $0.performedAt) }).count

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                PRCardView(
                    title: "Best Weight",
                    value: bestWeightEntry.map {
                        let formatted = Formatters.weight.string(from: NSNumber(value: $0.weight ?? 0)) ?? "\($0.weight ?? 0)"
                        return "\(formatted) \($0.weightUnit.symbol)"
                    } ?? "-"
                )
                PRCardView(title: "Best Reps", value: bestReps.map { "\($0) reps" } ?? "-")
            }
            HStack(spacing: 12) {
                PRCardView(title: "Longest Duration", value: bestDuration.map { DateHelper.formattedDuration(seconds: $0) } ?? "-")
                PRCardView(title: "Sessions", value: "\(sessionCount)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prCardsAccessibilityLabel(
            bestWeightEntry: bestWeightEntry,
            bestReps: bestReps,
            bestDuration: bestDuration,
            sessionCount: sessionCount
        ))
        .accessibilityIdentifier("Trends.PRCards")
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

    private var progressPoints: [ExerciseProgressPoint] {
        guard let selectedExercise else { return [] }
        return ExerciseProgressBuilder.buildPoints(entries: entries, exercise: selectedExercise, range: range)
    }

    private func setsLabel(for count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    private func selectDay(_ date: Date) {
        selectedWeekStart = nil
        selectedDay = date
    }

    private func selectWeekStart(_ date: Date) {
        selectedDay = nil
        selectedWeekStart = date
    }

    private func clearSelections() {
        selectedDay = nil
        selectedWeekStart = nil
        sheetDestination = nil
    }

    private func prCardsAccessibilityLabel(
        bestWeightEntry: SetEntry?,
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

        let repsText = bestReps.map { "Best reps \($0)" } ?? "Best reps none"
        let durationText = bestDuration.map { "Longest duration \(DateHelper.formattedDuration(seconds: $0))" } ?? "Longest duration none"
        let sessionsText = "Sessions \(sessionCount)"
        return [weightText, repsText, durationText, sessionsText].joined(separator: ", ")
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
        let base = Theme.secondaryTextColor(for: scheme)
        switch self {
        case .weighted:
            return base.opacity(scheme == .dark ? 0.9 : 0.7)
        case .reps:
            return base.opacity(scheme == .dark ? 0.75 : 0.55)
        case .duration:
            return base.opacity(scheme == .dark ? 0.6 : 0.45)
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
