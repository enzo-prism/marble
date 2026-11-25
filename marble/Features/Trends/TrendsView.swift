import SwiftUI
import SwiftData
import Charts
import os

/// Thin shell that owns the selected range so the content view below can
/// rebuild its `@Query` predicates whenever the range changes. SwiftData
/// queries are configured at init, so date-scoping them requires the scoping
/// input to arrive *through* init — the documented dynamic-query pattern.
/// This finally range-scopes the app's heaviest fetches instead of loading
/// every row ever logged on every data change.
struct TrendsView: View {
    @State private var range: TrendRange

    private let initialExercise: Exercise?
    private let initialSelectedDay: Date?
    private let initialSelectedWeekStart: Date?
    private let initialSupplementType: SupplementType?
    private let initialSelectedSupplementDay: Date?
    private let prioritizesInitialDetail: Bool
    private let initiallyShowsDetails: Bool

    init(
        initialRange: TrendRange = .thirtyDays,
        initialExercise: Exercise? = nil,
        initialSelectedDay: Date? = nil,
        initialSelectedWeekStart: Date? = nil,
        initialSupplementType: SupplementType? = nil,
        initialSelectedSupplementDay: Date? = nil,
        prioritizesInitialDetail: Bool = false,
        initiallyShowsDetails: Bool = false
    ) {
        _range = State(initialValue: initialRange)
        self.initialExercise = initialExercise
        self.initialSelectedDay = initialSelectedDay
        self.initialSelectedWeekStart = initialSelectedWeekStart
        self.initialSupplementType = initialSupplementType
        self.initialSelectedSupplementDay = initialSelectedSupplementDay
        self.prioritizesInitialDetail = prioritizesInitialDetail
        self.initiallyShowsDetails = initiallyShowsDetails
    }

    var body: some View {
        TrendsContentView(
            range: $range,
            initialExercise: initialExercise,
            initialSelectedDay: initialSelectedDay,
            initialSelectedWeekStart: initialSelectedWeekStart,
            initialSupplementType: initialSupplementType,
            initialSelectedSupplementDay: initialSelectedSupplementDay,
            prioritizesInitialDetail: prioritizesInitialDetail,
            initiallyShowsDetails: initiallyShowsDetails
        )
    }
}

struct TrendsContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    // Declared (not read) so the environment change invalidates this view:
    // range buckets anchored to "today" must re-derive on a new day.
    @Environment(\.marbleActiveDay) private var activeDay

    /// Sessions per week that count as a hit week (see TrainingConsistency).
    /// Stored in `SharedDefaults.suite`. The widget does not read this key —
    /// `WeeklyGoalWidgetPublisher` bakes the resolved target into the snapshot
    /// it publishes, which is why no cross-process store is needed.
    @AppStorage(SharedDefaults.Key.weeklySessionTarget, store: SharedDefaults.suite)
    private var weeklyTarget = TrainingConsistency.defaultWeeklyTarget

    @AppStorage(SharedDefaults.Key.dailyHighlightsEnabled, store: SharedDefaults.suite)
    private var dailyHighlightsEnabled = true

    @AppStorage(SharedDefaults.Key.dailyHighlightsStartMinute, store: SharedDefaults.suite)
    private var dailyHighlightsStartMinute = DailyHighlightWindow.defaultStartMinute

    @AppStorage(SharedDefaults.Key.dailyHighlightsEndMinute, store: SharedDefaults.suite)
    private var dailyHighlightsEndMinute = DailyHighlightWindow.defaultEndMinute

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    /// Scoped to the selected range at init (see `TrendsView`): only rows the
    /// charts can actually show are fetched and kept live. "All" keeps the
    /// unbounded fetch — that's what the user asked to see.
    @Query private var entries: [SetEntry]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query private var supplementEntries: [SupplementEntry]

    @Query(sort: \SupplementType.name)
    private var supplementTypes: [SupplementType]

    /// One-row freshness probes for the memo signature (see LatestUpdateQueries).
    @Query(LatestUpdateQueries.setEntry)
    private var latestUpdatedEntries: [SetEntry]

    @Query(LatestUpdateQueries.supplementEntry)
    private var latestUpdatedSupplements: [SupplementEntry]

    /// Freshness probe only. An **unbounded live `@Query`** for weigh-ins here
    /// hung the Trends render outright (caught by `testTrendsPopulated`, which
    /// timed out at three minutes): this view already keeps six live queries and
    /// re-derives inside them. The rows themselves are fetched once per memo
    /// rebuild by `fetchBodyMetrics()`, the same one-shot pattern
    /// `fetchHistoryEntries()` uses.
    @Query(LatestUpdateQueries.bodyMetricEntry)
    private var latestUpdatedBodyMetrics: [BodyMetricEntry]

    @Binding private var range: TrendRange
    @State private var selectedExerciseID: UUID?
    @State private var selectedSupplementTypeID: UUID?
    @State private var selectedDay: Date?
    @State private var selectedWeekStart: Date?
    @State private var selectedSupplementDay: Date?
    @State private var sheetDestination: TrendsSheetDestination?
    @State private var isPresentingExerciseSearch = false
    @State private var isScrubbingChart = false
    @State private var monthlyReportForSheet: MonthlyReport?
    @State private var showsDetailedAnalytics = false
    @State private var isPresentingWeightEntry = false
    @State private var isPresentingWeightHistory = false
    @State private var isPresentingDailyHighlightsSettings = false
    /// `@Query` updates cover rows in the visible range, while a context save
    /// notification also catches deletion of older history used by lifetime
    /// consistency and record analytics.
    @State private var dataRevision = 0
    private let prioritizesInitialDetail: Bool

    // Caches the derived snapshot so scrubbing a chart (which mutates UI-only
    // state and re-runs `body`) doesn't re-filter/-group/-sort the full history
    // every frame. Rebuilt only when the signature below changes.
    @State private var derivedMemo = RenderMemo<TrendsInputSignature, TrendsDerivedData>()
    // The overview card is lifetime-scoped, so it reads full history; cache it
    // so that one-shot fetch runs per data change, not per render.
    @State private var topExercisesMemo = RenderMemo<TopExercisesSignature, [TrendsShareCardRow]>()

    init(
        range: Binding<TrendRange>,
        initialExercise: Exercise? = nil,
        initialSelectedDay: Date? = nil,
        initialSelectedWeekStart: Date? = nil,
        initialSupplementType: SupplementType? = nil,
        initialSelectedSupplementDay: Date? = nil,
        prioritizesInitialDetail: Bool = false,
        initiallyShowsDetails: Bool = false
    ) {
        _range = range
        _selectedExerciseID = State(initialValue: initialExercise?.id)
        _selectedDay = State(initialValue: initialSelectedDay)
        _selectedWeekStart = State(initialValue: initialSelectedWeekStart)
        _selectedSupplementTypeID = State(initialValue: initialSupplementType?.id)
        _selectedSupplementDay = State(initialValue: initialSelectedSupplementDay)
        self.prioritizesInitialDetail = prioritizesInitialDetail
        _showsDetailedAnalytics = State(
            initialValue: prioritizesInitialDetail || initiallyShowsDetails)

        // Rebuilt whenever the range changes (the shell re-inits this view):
        // ranged modes fetch only rows on/after the range start, served by the
        // performedAt/takenAt indexes.
        if let startDate = range.wrappedValue.startDate {
            _entries = Query(
                filter: #Predicate<SetEntry> { $0.performedAt >= startDate },
                sort: \SetEntry.performedAt,
                order: .reverse
            )
            _supplementEntries = Query(
                filter: #Predicate<SupplementEntry> { $0.takenAt >= startDate },
                sort: \SupplementEntry.takenAt,
                order: .reverse
            )
        } else {
            _entries = Query(sort: \SetEntry.performedAt, order: .reverse)
            _supplementEntries = Query(sort: \SupplementEntry.takenAt, order: .reverse)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxl) {
                        if showsDetailedAnalytics {
                            let signature = currentInputSignature(highlightOccurrence: nil)
                            let derived = derivedMemo.value(for: signature) {
                                makeDerivedData(highlightOccurrence: nil)
                            }
                            let hasSetData = !derived.filteredEntries.isEmpty
                            let hasSupplementData = !derived.filteredSupplementEntries.isEmpty
                            let contentWidth = max(0, min(proxy.size.width, MarbleLayout.dashboardMaxWidth) - 2 * MarbleLayout.pagePadding)

                            ProgressDetailHeading(section: .summary)

                            rangePicker

                            if hasSetData || hasSupplementData {
                                TrendsPulseCard(
                                    derived: derived,
                                    range: range,
                                    displayWeightUnit: displayWeightUnit,
                                    supplementFilterName: selectedSupplementType?.name
                                )
                            }

                            TimedDailyHighlightsSection(
                                enabled: dailyHighlightsEnabled,
                                window: dailyHighlightWindow,
                                availableWidth: max(0, min(proxy.size.width, MarbleLayout.dashboardMaxWidth) - 2 * MarbleLayout.pagePadding),
                                displayWeightUnit: WeightUnit(rawValue: preferredWeightUnitRaw)
                                    ?? .lb,
                                latestEntryUpdate: latestUpdatedEntries.first?.updatedAt
                                    ?? .distantPast,
                                onCustomize: { isPresentingDailyHighlightsSettings = true }
                            )

                            if derived.consistencySnapshot.lifetimeSets > 0
                                && !prioritizesInitialDetail
                            {
                                TrendsFocusView(
                                    snapshot: derived.consistencySnapshot,
                                    weeklyTarget: $weeklyTarget,
                                    report: derived.monthlyReport,
                                    assessments: derived.strengthAssessments,
                                    onSelectExercise: { selectedExerciseID = $0 },
                                    onOpenReport: { monthlyReportForSheet = $0 }
                                )
                            }

                            if !hasSetData && !hasSupplementData {
                                EmptyStateView(
                                    title: "No trend data yet",
                                    message: "Log sets or supplements to see trends.",
                                    systemImage: "chart.line.uptrend.xyaxis"
                                )
                                .accessibilityIdentifier("Trends.EmptyState")
                            } else {
                                ProgressDetailHeading(section: .training)

                                if let liftBests = derived.liftBests {
                                    LiftBestsHighlightView(bests: liftBests)
                                }

                                if hasSetData {
                                    consistencySection(derived: derived, contentWidth: contentWidth)

                                    if selectedExercise == nil, !derived.strengthAssessments.isEmpty
                                    {
                                        StrengthDashboardView(
                                            assessments: derived.strengthAssessments
                                        ) { exerciseID in
                                            selectedExerciseID = exerciseID
                                        }
                                    }

                                    if selectedExercise != nil {
                                        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                                                TrendsGlyphBadge(
                                                    systemName: "chart.line.uptrend.xyaxis",
                                                    accent: TrendsPalette.progress.color(for: colorScheme),
                                                    size: 26
                                                )
                                                TrendsSectionHeader(
                                                    title: "Progress",
                                                    subtitle: selectedExerciseName,
                                                    takeaway: derived.progressPoints.count > 1
                                                        ? derived.progressPoints.last?.bestSetSummary : nil
                                                )
                                            }
                                            if derived.progressPoints.isEmpty {
                                                Text("No progress yet")
                                                    .font(MarbleTypography.rowMeta)
                                                    .foregroundStyle(
                                                        Theme.secondaryTextColor(for: colorScheme))
                                            } else if derived.progressPoints.count == 1,
                                                      let only = derived.progressPoints.first {
                                                TrendsSingleSessionNote(
                                                    date: only.date,
                                                    valueText: only.bestSetSummary,
                                                    accent: TrendsPalette.progress.color(for: colorScheme),
                                                    identifier: "Trends.Progress.SingleSession"
                                                )
                                            } else {
                                                ExerciseProgressChart(
                                                    points: derived.progressPoints,
                                                    isScrubbing: $isScrubbingChart
                                                ) { date in
                                                    sheetDestination = .day(date)
                                                }
                                            }
                                        }
                                        .trendsCard()

                                        if let oneRepMaxSeries = derived.oneRepMaxSeries {
                                            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                                OneRepMaxSectionView(
                                                    series: oneRepMaxSeries,
                                                    accessibilityValue: derived
                                                        .oneRepMaxAccessibilityValue
                                                )
                                                // Renders nothing unless a bodyweight
                                                // sits within 14 days of a training day.
                                                RelativeStrengthLine(series: oneRepMaxSeries)
                                            }
                                        }

                                        if let hint = derived.doubleProgressionHint {
                                            DoubleProgressionHintView(hint: hint)
                                        }

                                        if !derived.repRecords.isEmpty {
                                            RepRecordsSectionView(records: derived.repRecords)
                                        }
                                    }

                                    volumeChart(derived: derived)

                                    if !derived.muscleCoverage.isEmpty {
                                        MuscleGroupSectionView(
                                            groups: derived.muscleCoverage,
                                            accessibilityValue: derived
                                                .muscleGroupAccessibilityValue
                                        )
                                    }

                                    if !derived.repRangeBuckets.isEmpty {
                                        RepRangeSectionView(buckets: derived.repRangeBuckets)
                                    }

                                    if derived.effortSummaries.count > 1 {
                                        EffortSectionView(
                                            summaries: derived.effortSummaries,
                                            usesWeeks: consistencyUsesWeeks,
                                            accessibilityValue: derived.effortAccessibilityValue
                                        )
                                    }
                                } else {
                                    Text("No workout data for this range.")
                                        .font(MarbleTypography.rowMeta)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                }

                                ProgressDetailHeading(section: .bodyAndHabits)

                                // Outside the hasSetData guard on purpose: a user with
                                // no sets in range can still be invited to weigh in.
                                BodyweightTrendSection(
                                    range: range,
                                    onLogWeight: { isPresentingWeightEntry = true },
                                    onShowHistory: { isPresentingWeightHistory = true }
                                )

                                supplementsSection(derived: derived)

                                if hasSetData {
                                    ProgressDetailHeading(section: .milestones)
                                }

                                if hasSetData, !derived.prEvents.isEmpty {
                                    PRFeedSectionView(events: derived.prEvents)
                                }

                                if hasSetData {
                                    SprintTrendsSection(
                                        entries: entries,
                                        latestEntryUpdate: latestUpdatedEntries.first?.updatedAt
                                            ?? .distantPast
                                    )
                                }

                                if hasSetData {
                                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                                        // Range-scoped bests — distinct on purpose from
                                        // the all-time records in the feed above.
                                        TrendsSectionHeader(
                                            title: "Range Bests",
                                            subtitle: range.spanTitle,
                                            hidesTitleFromAccessibility: true
                                        )
                                        .accessibilityHidden(true)
                                        prCards(derived: derived)
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: MarbleSpacing.xl) {
                                TrendsShareCardView(rows: lifetimeTopExercises)
                                .padding(.horizontal, MarbleSpacing.xs)
                                ProgressQuoteFooter(
                                    day: activeDay,
                                    availableWidth: max(0, min(proxy.size.width, MarbleLayout.dashboardMaxWidth) - 2 * MarbleLayout.pagePadding)
                                )
                            }
                            .frame(
                                minHeight: max(proxy.size.height - MarbleSpacing.xxl, 0),
                                alignment: .topLeading
                            )
                        }
                    }
                    .padding(MarbleLayout.pagePadding)
                    .frame(maxWidth: MarbleLayout.dashboardMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: MarbleSpacing.xxl)
                        .accessibilityHidden(true)
                }
                .scrollDisabled(isScrubbingChart)
                .accessibilityIdentifier("Trends.Scroll")
            }
            .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Progress")
            .navigationSubtitle(showsDetailedAnalytics ? selectedExerciseName : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar { progressToolbar }
            .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
        }
        .sheet(item: $sheetDestination) { destination in
            Group {
                switch destination {
                case .day(let date):
                    DayDetailsSheet(date: date, entries: entriesForDay(date))
                case .week(let weekStart):
                    let weekEnd = TrendsDateHelper.endOfWeek(for: weekStart)
                    WeekDetailsSheet(
                        weekStart: weekStart, weekEnd: weekEnd,
                        entries: entriesForWeek(weekStart: weekStart))
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
        .sheet(item: $monthlyReportForSheet) { report in
            MonthlyReportSheet(report: report)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .sheet(isPresented: $isPresentingWeightEntry) {
            BodyMetricEntryView()
        }
        .sheet(isPresented: $isPresentingWeightHistory) {
            BodyMetricHistoryView()
                .presentationDetents([.large])
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
        .sheet(isPresented: $isPresentingDailyHighlightsSettings) {
            DailyHighlightsSettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .onChange(of: range) { _, _ in
            MarbleHaptics.selection()
            clearSelections()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave,
                object: modelContext
            )
        ) { _ in
            dataRevision &+= 1
        }
        .onChange(of: selectedExerciseID) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedSupplementTypeID) { _, _ in
            clearSelections()
        }
        .onChange(of: selectedDay) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit,
                !TestHooks.isAppStoreScreenshotting
            else { return }
            if let day = newValue {
                sheetDestination = .day(Calendar.current.startOfDay(for: day))
            }
        }
        .onChange(of: selectedWeekStart) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit,
                !TestHooks.isAppStoreScreenshotting
            else { return }
            if let weekStart = newValue {
                sheetDestination = .week(weekStart)
            }
        }
        .onChange(of: selectedSupplementDay) { _, newValue in
            guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit,
                !TestHooks.isAppStoreScreenshotting
            else { return }
            if let day = newValue {
                openSupplementDrilldown(for: day)
            }
        }
    }

    @ToolbarContentBuilder
    private var progressToolbar: some ToolbarContent {
        if showsDetailedAnalytics {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: showOverview) {
                    Text("Overview")
                        .font(MarbleTypography.button)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .frame(minHeight: MarbleLayout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .controlSize(.large)
                .accessibilityHint("Returns to the minimal Progress overview")
                .accessibilityIdentifier("Trends.Details.Overview")
            }

            ToolbarItem(placement: .topBarTrailing) {
                exerciseSearchButton
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showDetails) {
                    Text("Details")
                        .font(MarbleTypography.button)
                        .frame(minHeight: MarbleLayout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .controlSize(.large)
                .accessibilityHint("Shows goals, charts, records, body metrics, and supplements")
                .accessibilityIdentifier("Trends.Details.Toggle")
            }
        }
    }

    private func showDetails() {
        setDetailedAnalyticsVisible(true)
    }

    private func showOverview() {
        setDetailedAnalyticsVisible(false)
    }

    private func setDetailedAnalyticsVisible(_ isVisible: Bool) {
        // Building the full analytics tree is intentionally deferred until
        // Details opens. Insert it without a broad transition so large histories
        // do not compete with an animation; the lightweight return can animate.
        if reduceMotion || isVisible {
            showsDetailedAnalytics = isVisible
        } else {
            withAnimation(.snappy) {
                showsDetailedAnalytics = isVisible
            }
        }
        MarbleHaptics.selection()
    }

    private func makeDerivedData(highlightOccurrence: DailyHighlightOccurrence?) -> TrendsDerivedData {
        TrendsDerivedData.build(
            entries: entries,
            supplementEntries: supplementEntries,
            historyEntries: fetchHistoryEntries(),
            selectedExercise: selectedExercise,
            selectedSupplementType: selectedSupplementType,
            range: range,
            weeklyTarget: weeklyTarget,
            dailyHighlightOccurrence: highlightOccurrence,
            displayWeightUnit: WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb,
            bodyweights: fetchBodyMetrics().map { LifterAnalytics.BodyweightSample($0) }
        )
    }

    private var dailyHighlightWindow: DailyHighlightWindow {
        DailyHighlightWindow(
            startMinute: dailyHighlightsStartMinute,
            endMinute: dailyHighlightsEndMinute
        )
    }

    /// One-shot fetch of every weigh-in, for the monthly report's bodyweight
    /// facts. Unscoped by range on purpose — the report compares this month
    /// against the previous one, so clipping to the selected range would drop the
    /// comparison month. Runs only when the memo rebuilds.
    private func fetchBodyMetrics() -> [BodyMetricEntry] {
        let descriptor = FetchDescriptor<BodyMetricEntry>(
            sortBy: [SortDescriptor(\BodyMetricEntry.measuredAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// One-shot full-history fetch for the coaching layer (records, streaks,
    /// and verdicts describe the lifter, not the visible range). Runs only
    /// when the memo rebuilds — never per render — and reuses the live query
    /// when the range is already unbounded. The live freshness probe catches
    /// inserts/edits and `dataRevision` catches deletes outside the range.
    private func fetchHistoryEntries() -> [SetEntry] {
        let interval = HistoryPerformance.signposter.beginInterval("Progress full history")
        defer { HistoryPerformance.signposter.endInterval("Progress full history", interval) }
        if range == .all { return Array(entries) }
        let descriptor = FetchDescriptor<SetEntry>()
        return (try? modelContext.fetch(descriptor)) ?? Array(entries)
    }

    /// Lifetime Top Exercises for the overview, independent of `range`. The
    /// range-scoped `entries` query only feeds the signature: its count catches
    /// in-range inserts and deletes, the freshness probe catches edits, and
    /// `dataRevision` catches deletes and renames anywhere in history.
    private var lifetimeTopExercises: [TrendsShareCardRow] {
        let signature = TopExercisesSignature(
            entryCount: entries.count,
            exerciseCount: exercises.count,
            latestEntryUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast,
            activeDay: activeDay,
            dataRevision: dataRevision
        )
        return topExercisesMemo.value(for: signature) {
            TrendsShareCard.lifetimeTopExercises(in: modelContext)
        }
    }

    /// A cheap fingerprint of everything `makeDerivedData()` actually depends on.
    /// Counts catch inserts/deletes; the latest `updatedAt` catches in-place
    /// edits (the app stamps it on every edit); the selected exercise's name
    /// catches a rename of the one exercise whose fields feed the progress chart.
    private func currentInputSignature(highlightOccurrence: DailyHighlightOccurrence?) -> TrendsInputSignature {
        TrendsInputSignature(
            entryCount: entries.count,
            supplementCount: supplementEntries.count,
            exerciseCount: exercises.count,
            latestEntryUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast,
            latestSupplementUpdate: latestUpdatedSupplements.first?.updatedAt ?? .distantPast,
            range: range,
            selectedExerciseID: selectedExerciseID,
            selectedSupplementTypeID: selectedSupplementTypeID,
            selectedExerciseName: selectedExercise?.name,
            activeDay: activeDay,
            weeklyTarget: weeklyTarget,
            highlightCelebrationDay: highlightOccurrence?.celebrationDay,
            dailyHighlightsEnabled: dailyHighlightsEnabled,
            dailyHighlightsStartMinute: dailyHighlightsStartMinute,
            dailyHighlightsEndMinute: dailyHighlightsEndMinute,
            preferredWeightUnitRaw: preferredWeightUnitRaw,
            latestBodyweightUpdate: latestUpdatedBodyMetrics.first?.updatedAt ?? .distantPast,
            dataRevision: dataRevision
        )
    }

    /// Long ranges aggregate the consistency and supplement charts to weekly
    /// buckets so mark counts stay proportional to what the chart can show.
    private var consistencyUsesWeeks: Bool {
        range == .oneYear || range == .all
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

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: MarbleSpacing.s) {
                Text("Range")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Spacer(minLength: MarbleSpacing.s)

                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Range")
            }
            .frame(minHeight: 44)
        } else {
            Picker("Range", selection: $range) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityIdentifier("Trends.Range")
        }
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

    private var displayWeightUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    private func consistencySection(derived: TrendsDerivedData, contentWidth: CGFloat) -> some View {
        let heatmap = derived.heatmap
        let accent = TrendsPalette.consistency.color(for: colorScheme)
        let selectedSummary = selectedHeatmapSummary(in: derived)
        let takeaway = range == .all
            ? "\(heatmap.activeDays) active days"
            : "\(heatmap.activeDays) of \(heatmap.days.count) days"
        let subtitle = TrendsHeatmapGeometry.style(forDayCount: heatmap.days.count) == .months
            ? "Past 12 months, one square per day"
            : "\(range.spanTitle), one square per day"

        return VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            TrendsSectionHeader(
                title: "Consistency",
                subtitle: subtitle,
                takeaway: takeaway,
                takeawayGlyph: "checkmark.circle.fill",
                accent: accent
            )

            TrendsConsistencyHeatmap(
                model: heatmap,
                availableWidth: contentWidth - 2 * TrendsLayout.cardPadding,
                selectedDate: selectedDay,
                accessibilityValue: derived.consistencyAccessibilityValue,
                audioGraph: TrendsDateSeriesAudioGraph(
                    title: "Consistency",
                    summary: derived.consistencyAccessibilityValue,
                    valueAxisName: "Sets",
                    valueUnit: "sets",
                    seriesName: "Sets",
                    points: heatmap.days.map {
                        .init(date: $0.date, value: Double($0.count), valueText: setsLabel(for: $0.count))
                    }
                ),
                onSelectDay: selectDay
            )

            TrendsStatRow(stats: consistencyStats(heatmap))

            if let selectedSummary {
                let title = DateHelper.dayLabel(for: selectedSummary.date)
                TrendTooltipView(
                    title: title,
                    valueText: selectedSummary.count == 0 ? "Rest day" : setsLabel(for: selectedSummary.count),
                    summaryText: selectedSummary.count == 0 ? nil : selectedSummary.summaryText,
                    showsPR: heatmap.day(for: selectedSummary.date, calendar: .current)?.hasPR == true,
                    viewSetsLabel: "View sets",
                    viewSetsAccessibilityLabel: "View sets for \(title)",
                    viewSetsIdentifier: "Trends.ConsistencyTooltip.ViewSets",
                    onViewSets: {
                        sheetDestination = .day(selectedSummary.date)
                    },
                    onClear: {
                        selectedDay = nil
                    }
                )
                .accessibilityIdentifier("Trends.ConsistencyTooltip")
            }
        }
        .trendsCard()
    }

    private func consistencyStats(_ heatmap: TrendsHeatmapModel) -> [TrendsStat] {
        let accent = TrendsPalette.consistency.color(for: colorScheme)
        var stats = [
            TrendsStat(
                symbol: "flame.fill",
                accent: accent,
                value: "\(heatmap.currentStreak)",
                unit: heatmap.currentStreak == 1 ? "day" : "days",
                label: "Current streak"
            ),
            TrendsStat(
                symbol: "arrow.up.forward",
                accent: accent,
                value: "\(heatmap.longestStreak)",
                unit: heatmap.longestStreak == 1 ? "day" : "days",
                label: "Longest streak"
            )
        ]
        if let weekday = heatmap.busiestWeekday {
            stats.append(TrendsStat(
                symbol: "calendar",
                accent: accent,
                value: Calendar.current.shortWeekdaySymbols[weekday - 1],
                unit: nil,
                label: "Most active"
            ))
        }
        return stats
    }

    private func selectedHeatmapSummary(in derived: TrendsDerivedData) -> TrendDailySummary? {
        guard let selectedDay else { return nil }
        let day = Calendar.current.startOfDay(for: selectedDay)
        return derived.daySummaries[day] ?? TrendDailySummary(date: day, entries: [])
    }

    private func volumeChart(derived: TrendsDerivedData) -> some View {
        TrendsWeeklyVolumeChart(
            derived: derived,
            selectedSummary: selectedWeeklySummary(in: derived),
            chartHeight: chartHeight,
            isScrubbingChart: $isScrubbingChart,
            onSelectWeek: selectWeekStart,
            onViewSets: { sheetDestination = .week($0) },
            onClearSelection: { selectedWeekStart = nil }
        )
    }

    private var supplementsTitle: some View {
        HStack(alignment: .center) {
            TrendsGlyphBadge(
                systemName: "pills.fill",
                accent: TrendsPalette.supplements.color(for: colorScheme),
                size: 24
            )
            Text("Supplements")
                .font(TrendsFont.section)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    private func supplementsSection(derived: TrendsDerivedData) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            // The filter menu sits beside the title when it fits on one line
            // and drops beneath it otherwise, so a long supplement name never
            // wraps into the chart.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    supplementsTitle
                    Spacer(minLength: MarbleSpacing.s)
                    supplementPicker.fixedSize()
                }
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    supplementsTitle
                    supplementPicker
                }
            }

            if !derived.filteredSupplementEntries.isEmpty {
                supplementsTakeaway(derived: derived)
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
        .trendsCard()
    }

    /// Leads with the takeaway, like every other Details card: how much was
    /// logged and on how many days, then what each bar measures.
    private func supplementsTakeaway(derived: TrendsDerivedData) -> some View {
        let logged = derived.supplementSummariesWithLogs
        let logs = logged.reduce(0) { $0 + $1.count }
        let bucket = consistencyUsesWeeks ? "week" : "day"
        let buckets = logged.count
        let measure: String = {
            switch logged.first?.mode ?? derived.supplementSummaries.first?.mode {
            case .dose(let unit): return "Total dose per \(bucket), in \(unit.displayName)"
            default: return "Logs per \(bucket)"
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(logs) \(logs == 1 ? "log" : "logs") on \(buckets) \(buckets == 1 ? bucket : bucket + "s")")
                .font(TrendsFont.takeaway)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text(measure)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Trends.Supplements.Takeaway")
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
        let chartDomain = paddedDateDomain(dataRange, component: consistencyUsesWeeks ? .weekOfYear : .day, value: 1)

        let accent = TrendsPalette.supplements.color(for: colorScheme)

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            // Each mark is a daily (or weekly) total, so bars — not a smoothed
            // line, which drew peaks between days that were never logged
            // (HIG Charts: bars for sums, lines mislead across gaps).
            Chart {
                ForEach(summaries.filter { $0.chartValue > 0 }) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: consistencyUsesWeeks ? .weekOfYear : .day),
                        y: .value("Value", item.chartValue),
                        width: .ratio(consistencyUsesWeeks ? 0.7 : 0.8)
                    )
                    .cornerRadius(consistencyUsesWeeks ? 4 : 3)
                    .foregroundStyle(
                        selectedSummary == nil || selectedSummary?.date == item.date
                            ? AnyShapeStyle(accent)
                            : AnyShapeStyle(accent.opacity(colorScheme == .dark ? 0.42 : 0.32))
                    )
                    .accessibilityHidden(true)
                }
            }
            .frame(height: chartHeight)
            .chartDateDomain(chartDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis { TrendsAxes.date(scheme: colorScheme) }
            .chartYAxis { TrendsAxes.value(scheme: colorScheme, desiredCount: 3) }
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
                            accessibilityValue: derived.supplementAccessibilityValue,
                            audioGraph: TrendsDateSeriesAudioGraph(
                                title: "Supplements",
                                summary: derived.supplementAccessibilityValue,
                                valueAxisName: "Doses",
                                valueUnit: nil,
                                seriesName: "Doses",
                                points: summaries.map {
                                    .init(date: $0.date, value: $0.chartValue, valueText: $0.valueText)
                                }
                            ),
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
        // Bests are derived once in `TrendsDerivedData.build()` (see the cached
        // snapshot) instead of re-scanning `filteredEntries` on every render.
        let bestWeightEntry = derived.bestWeightEntry
        let bestDistanceEntry = derived.bestDistanceEntry
        let fastestSpeedEntry = derived.fastestSpeedEntry
        let bestReps = derived.bestReps
        let bestDuration = derived.bestDuration
        let sessionCount = derived.activeDayCount
        let showsDistancePRs = bestDistanceEntry != nil

        let firstCard = PRCardMetric(
            title: showsDistancePRs ? "Best Distance" : "Best Weight",
            value: showsDistancePRs
                ? bestDistanceEntry.map { $0.exercise.formattedDistanceSummary($0.distance ?? 0, unit: $0.distanceUnit) } ?? "-"
                : bestWeightEntry.map { $0.exercise.formattedWeightSummary($0.weight ?? 0, unit: $0.weightUnit) } ?? "-",
            systemImage: showsDistancePRs ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "scalemass.fill",
            accent: showsDistancePRs ? TrendsPalette.sprint : TrendsPalette.volumeWeighted
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
                : bestReps.map { "\($0) reps" } ?? "-",
            systemImage: showsDistancePRs ? "hare.fill" : "repeat",
            accent: showsDistancePRs ? TrendsPalette.endurance : TrendsPalette.volumeReps
        )
        let thirdCard = PRCardMetric(
            title: "Longest Duration",
            value: bestDuration.map { DateHelper.formattedDuration(seconds: $0) } ?? "-",
            systemImage: "timer",
            accent: TrendsPalette.volumeDuration
        )
        let fourthCard = PRCardMetric(
            title: "Sessions",
            value: "\(sessionCount)",
            systemImage: "calendar",
            accent: TrendsPalette.consistency
        )

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    prCard(firstCard)
                    prCard(secondCard)
                    prCard(thirdCard)
                    prCard(fourthCard)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        prCard(firstCard)
                        prCard(secondCard)
                    }
                    HStack(spacing: 12) {
                        prCard(thirdCard)
                        prCard(fourthCard)
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

    private func prCard(_ metric: PRCardMetric) -> PRCardView {
        PRCardView(
            title: metric.title,
            value: metric.value,
            systemImage: metric.systemImage,
            accent: metric.accent.color(for: colorScheme)
        )
    }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 180
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
        if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit, !TestHooks.isAppStoreScreenshotting {
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

extension View {
    @ViewBuilder
    func chartDateDomain(_ domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain)
        } else {
            self
        }
    }
}

private struct PRCardMetric {
    let title: String
    let value: String
    let systemImage: String
    let accent: TrendsChartAccent
}

/// Owns the only minute-level clock on Trends. Keeping the TimelineView in
/// this leaf prevents the navigation stack, ScrollView, and every chart from
/// rebuilding once per minute just to cross the celebration-window boundary.
private struct TimedDailyHighlightsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var memo = RenderMemo<TimedDailyHighlightsSignature, DailyHighlightSummary?>()

    let enabled: Bool
    let window: DailyHighlightWindow
    let availableWidth: CGFloat
    let displayWeightUnit: WeightUnit
    let latestEntryUpdate: Date
    let onCustomize: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if enabled,
               let occurrence = window.occurrence(containing: AppEnvironment.now) {
                // Freshness probe. This used to be a full-table `fetchCount`
                // on every minute tick and parent-driven render — the count
                // existed only to catch deletions, which the one-row
                // `updatedAt` probe cannot see. The latest history-transaction
                // token catches inserts, edits, *and* deletes with a one-row
                // indexed read, so re-derivation still happens exactly when
                // the store changed. `latestEntryUpdate` stays in the
                // signature both as the eager SwiftUI dependency (it arrives
                // through a live parent @Query) and as the fallback signal for
                // stores without history (see `HistoryTokenQueries`).
                let historyToken = HistoryTokenQueries.latestTransactionIdentifier(in: modelContext)
                let signature = TimedDailyHighlightsSignature(
                    celebrationDay: occurrence.celebrationDay,
                    historyToken: historyToken,
                    latestEntryUpdate: latestEntryUpdate,
                    displayWeightUnit: displayWeightUnit
                )
                let summary = memo.value(for: signature) {
                    // Scoped to what the builder actually consumes (the day's
                    // rows plus the full prior history of just that day's
                    // exercises) instead of the entire SetEntry table; see
                    // `DailyHighlightQueries` for why the record baseline has
                    // no date cutoff. Runs only on a signature miss.
                    let history = DailyHighlightQueries.history(
                        for: occurrence,
                        in: modelContext
                    )
                    return DailyHighlightsBuilder.build(
                        history: history,
                        occurrence: occurrence,
                        now: AppEnvironment.now,
                        displayWeightUnit: displayWeightUnit
                    )
                }

                if let summary {
                    DailyHighlightsSection(
                        summary: summary,
                        occurrence: occurrence,
                        availableWidth: availableWidth,
                        onCustomize: onCustomize
                    )
                }
            }
        }
    }
}

private struct TimedDailyHighlightsSignature: Equatable {
    let celebrationDay: Date
    /// Latest persistent-history transaction identifier, or nil when the
    /// store records no history. Advances on any save — including deletions,
    /// which neither a latest-`updatedAt` probe nor a day-scoped count can see.
    let historyToken: Int64?
    let latestEntryUpdate: Date
    let displayWeightUnit: WeightUnit
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

    /// Shape cues keep grouped bars and their legend distinguishable without
    /// depending on color alone.
    var legendSymbol: TrendsLegendSymbol {
        switch self {
        case .weighted: .circle
        case .reps: .square
        case .duration: .triangle
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .weighted: 4
        case .reps: 0
        case .duration: 8
        }
    }
}

/// Cheap, `Equatable` fingerprint of the inputs `TrendsDerivedData.build()`
/// depends on, used to memoize the derived snapshot across renders.
struct TrendsInputSignature: Equatable {
    let entryCount: Int
    let supplementCount: Int
    let exerciseCount: Int
    let latestEntryUpdate: Date
    let latestSupplementUpdate: Date
    let range: TrendRange
    let selectedExerciseID: UUID?
    let selectedSupplementTypeID: UUID?
    let selectedExerciseName: String?
    let activeDay: Date
    let weeklyTarget: Int
    let highlightCelebrationDay: Date?
    let dailyHighlightsEnabled: Bool
    let dailyHighlightsStartMinute: Int
    let dailyHighlightsEndMinute: Int
    let preferredWeightUnitRaw: String
    /// Weigh-ins feed the monthly report's bodyweight facts, so logging or
    /// editing one has to invalidate the memo. Same one-row `updatedAt` probe the
    /// set and supplement signatures use.
    let latestBodyweightUpdate: Date
    /// Context-save fallback catches deletions that leave one-row latest-update
    /// probes unchanged, including history outside the selected range.
    let dataRevision: Int
}

/// Inputs the lifetime Top Exercises card depends on. `range` is left out on
/// purpose: the card must not change with the Details range picker.
/// `activeDay` refreshes the "Today"/"Yesterday" labels after midnight.
struct TopExercisesSignature: Equatable {
    let entryCount: Int
    let exerciseCount: Int
    let latestEntryUpdate: Date
    let activeDay: Date
    let dataRevision: Int
}

/// `nonisolated`: this value carries no UI state and is safe to pass into pure
/// analytics work regardless of the caller's actor.
nonisolated enum TrendRange: String, CaseIterable, Identifiable {
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
            // Inclusive of today like the day ranges above (7D is 7 days), so
            // the window holds one year of days — 365 or 366, never 367.
            let today = calendar.startOfDay(for: AppEnvironment.now)
            return calendar.date(byAdding: .year, value: -1, to: today)
                .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        case .all:
            return nil
        }
    }
}
