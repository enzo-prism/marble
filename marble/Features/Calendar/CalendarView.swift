import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @Environment(QuickLogCoordinator.self) private var quickLog
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.marbleActiveDay) private var activeDay

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \ProgressMediaAttachment.createdAt, order: .reverse)
    private var progressMediaAttachments: [ProgressMediaAttachment]

    @State private var selectedDay: CalendarSelection?
    @State private var selectedDate: Date?
    @State private var visibleMonth = Calendar.current.dateComponents([.year, .month], from: AppEnvironment.now)
    @State private var didOpenRequestedTestDay = false

    // Active-day markers, streak, and the selected-day summary all come from one
    // walk over the queried models. Memoized so paging the month grid (which only
    // changes `visibleMonth`, not the derivation inputs) reuses the result instead
    // of re-walking the full history on every tap.
    @State private var derivedMemo = RenderMemo<CalendarInputSignature, CalendarDerivedData>()

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    let derived = deriveCalendarData()
                    VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                        if TestHooks.isUITesting && !TestHooks.isAccessibilityAudit {
                            testControlsRow
                        }

                        calendarHeader(streak: derived.streak)

                        calendarActionRow(metrics: derived.daySummary)

                        calendarMonthSection(activeDays: derived.activeDays)
                    }
                    .padding(.horizontal, MarbleLayout.pagePadding)
                    .padding(.bottom, MarbleSpacing.xxl)
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .background(Theme.backgroundColor(for: colorScheme))
                .contentMargins(.top, calendarContentTopMargin, for: .scrollContent)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
        }
        .sheet(item: $selectedDay) { selectedDay in
            DaySummarySheet(date: selectedDay.date, entries: entriesForDay(selectedDay.date))
                .environment(quickLog)
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .onAppear {
            openRequestedTestDayIfNeeded()
        }
    }

    private struct CalendarDerivedData {
        let activeDays: Set<CalendarDayKey>
        let streak: Int
        let daySummary: CalendarSummaryMetrics
    }

    /// Cheap `Equatable` fingerprint of the inputs `deriveCalendarData()` reads.
    /// Notably excludes `visibleMonth`, so paging the grid reuses the cached walk.
    fileprivate struct CalendarInputSignature: Equatable {
        let entryCount: Int
        let latestEntryUpdate: Date
        let attachmentCount: Int
        let latestAttachmentUpdate: Date
        let headerDate: Date
        let activeDay: Date
    }

    /// One pass over the queried models: day markers, streak, and the
    /// selected-day summary all come out of the same walk. Memoized on the
    /// inputs it actually reads (see `derivedMemo`).
    private func deriveCalendarData() -> CalendarDerivedData {
        let signature = CalendarInputSignature(
            entryCount: entries.count,
            latestEntryUpdate: entries.reduce(Date.distantPast) { Swift.max($0, $1.updatedAt) },
            attachmentCount: progressMediaAttachments.count,
            latestAttachmentUpdate: progressMediaAttachments.reduce(Date.distantPast) { Swift.max($0, $1.updatedAt) },
            headerDate: headerDate,
            activeDay: activeDay
        )
        return derivedMemo.value(for: signature) {
            let targetDay = calendar.startOfDay(for: headerDate)
            var activeDays = Set<CalendarDayKey>(minimumCapacity: entries.count)
            var loggedDays = Set<Date>(minimumCapacity: entries.count)
            var dayEntries: [SetEntry] = []

            for entry in entries {
                let dayStart = calendar.startOfDay(for: entry.performedAt)
                loggedDays.insert(dayStart)
                activeDays.insert(CalendarDayKey(date: entry.performedAt, calendar: calendar))
                if dayStart == targetDay {
                    dayEntries.append(entry)
                }
            }

            for attachment in progressMediaAttachments {
                activeDays.insert(CalendarDayKey(date: attachment.attachedToDate, calendar: calendar))
            }

            return CalendarDerivedData(
                activeDays: activeDays,
                streak: currentStreak(loggedDays: loggedDays),
                daySummary: CalendarSummaryMetrics(
                    sets: dayEntries.count,
                    exercises: Set(dayEntries.map { $0.exercise.id }).count,
                    averageRPE: averageRPE(for: dayEntries)
                )
            )
        }
    }

    private func entriesForDay(_ date: Date) -> [SetEntry] {
        let start = calendar.startOfDay(for: date)
        return entries.filter { calendar.isDate($0.performedAt, inSameDayAs: start) }
    }

    private func openTestDay(mode: String) {
        let now = AppEnvironment.now
        let targetDate: Date
        switch mode {
        case "empty":
            targetDate = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        default:
            targetDate = now
        }
        selectedDate = targetDate
        presentDaySheet(for: targetDate)
    }

    private func openRequestedTestDayIfNeeded() {
        guard
            TestHooks.isUITesting,
            TestHooks.isAccessibilityAudit,
            let mode = TestHooks.calendarTestDay,
            !didOpenRequestedTestDay
        else { return }
        didOpenRequestedTestDay = true
        Task { @MainActor in
            await Task.yield()
            openTestDay(mode: mode)
        }
    }

    private func presentDaySheet(for date: Date) {
        let selection = CalendarSelection(date: date)
        guard selectedDay != nil else {
            selectedDay = selection
            return
        }

        selectedDay = nil
        Task { @MainActor in
            await Task.yield()
            selectedDay = selection
        }
    }

    private var testControlsRow: some View {
        HStack {
            Button("Open Empty Day") {
                openTestDay(mode: "empty")
            }
            .accessibilityIdentifier("Calendar.TestOpenEmpty")
            .accessibilityLabel("Open test day empty")
            .frame(minHeight: 44)
            .contentShape(Rectangle())

            Spacer()

            Button("Open Populated Day") {
                openTestDay(mode: "populated")
            }
            .accessibilityIdentifier("Calendar.TestOpenPopulated")
            .accessibilityLabel("Open test day with sets")
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .font(MarbleTypography.smallLabel)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .padding(.horizontal, 4)
    }

    private func calendarActionRow(metrics: CalendarSummaryMetrics) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            selectedDaySummaryCard(metrics: metrics)
            if !dynamicTypeSize.isAccessibilitySize {
                logSetButton
            }
        }
    }

    private func selectedDaySummaryCard(metrics: CalendarSummaryMetrics) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text("Selected day")
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)

            summaryMetricsView(
                setCount: metrics.sets,
                exerciseCount: metrics.exercises,
                averageRPE: metrics.averageRPE,
                emphasis: .primary
            )
        }
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityIdentifier("Calendar.SelectedDaySummary")
    }

    @ViewBuilder
    private var logSetButton: some View {
        Button(action: logSelectedDateSet) {
            Label("Log Set", systemImage: "plus")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
        .accessibilityIdentifier("Calendar.LogSet")
        .accessibilityHint("Logs a set for \(DateHelper.dayLabel(for: headerDate)).")
    }

    private func logSelectedDateSet() {
        let targetDate = selectedDate ?? AppEnvironment.now
        quickLog.open(prefillDate: targetDate)
    }

    private func calendarHeader(streak: Int) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    headerTitle
                    streakBadge(streak: streak)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                        headerTitle
                        Spacer(minLength: MarbleSpacing.s)
                        streakBadge(streak: streak)
                    }
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        headerTitle
                        streakBadge(streak: streak)
                    }
                }
            }

            Text(monthContextLine)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("Calendar.Header.Summary")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Calendar.Header")
    }

    private var headerTitle: some View {
        Text(DateHelper.dayLabel(for: headerDate))
            .font(MarbleTypography.sectionTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .accessibilityIdentifier("Calendar.Header.DayLabel")
    }

    @ViewBuilder
    private func streakBadge(streak: Int) -> some View {
        let streakLabel = streakLabel(for: streak)
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: "flame.fill")
                .accessibilityHidden(true)
            Text(streakLabel)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(MarbleTypography.smallLabel)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : MarbleSpacing.s)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : MarbleSpacing.xxs)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .background {
            if !dynamicTypeSize.isAccessibilitySize {
                Capsule()
                    .fill(Theme.chipFillColor(for: colorScheme))
            }
        }
        .overlay {
            if !dynamicTypeSize.isAccessibilitySize {
                Capsule()
                    .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
            }
        }
        .accessibilityLabel(streakLabel)
        .accessibilityIdentifier("Calendar.Header.Streak")
    }

    private var headerDate: Date {
        selectedDate ?? activeDay
    }

    private var monthContextLine: String {
        "Sets and progress media by day."
    }

    private var calendarContentTopMargin: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? MarbleSpacing.xl : MarbleSpacing.l
    }

    private var calendarMonthTopGap: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? MarbleSpacing.m : MarbleSpacing.s
    }

    private func streakLabel(for count: Int) -> String {
        let dayLabel = pluralize(count: count, singular: "day", plural: "days")
        return "Streak \(count) \(dayLabel)"
    }

    private func currentStreak(loggedDays: Set<Date>) -> Int {
        guard !loggedDays.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: AppEnvironment.now)
        let streakEnd: Date?
        if loggedDays.contains(today) {
            streakEnd = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  loggedDays.contains(yesterday) {
            streakEnd = yesterday
        } else {
            streakEnd = nil
        }
        guard let start = streakEnd else { return 0 }
        var count = 0
        var cursor = start
        while loggedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }
        return count
    }

    private func averageRPE(for entries: [SetEntry]) -> String {
        guard !entries.isEmpty else { return "-" }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        let avg = Double(total) / Double(entries.count)
        return String(format: "%.1f", avg)
    }

    private func pluralize(count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    private func calendarMonthSection(activeDays: Set<CalendarDayKey>) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: calendarMonthTopGap)
                .accessibilityHidden(true)

            ZStack {
                CalendarRepresentable(
                    activeDays: activeDays,
                    visibleMonth: visibleMonth,
                    onSelect: { components in
                        guard let components, let date = calendar.date(from: components) else {
                            selectedDay = nil
                            selectedDate = nil
                            return
                        }
                        selectedDate = date
                        presentDaySheet(for: date)
                    },
                    onVisibleMonthChange: { components in
                        visibleMonth = components
                    }
                )
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Calendar.View")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("Calendar.MonthSection")
    }

    @ViewBuilder
    private func summaryMetricsView(
        setCount: Int,
        exerciseCount: Int,
        averageRPE: String,
        emphasis: CalendarSummaryMetricsView.Emphasis
    ) -> some View {
        CalendarSummaryMetricsView(
            metrics: CalendarSummaryMetrics(
                sets: setCount,
                exercises: exerciseCount,
                averageRPE: averageRPE
            ),
            emphasis: emphasis
        )
    }

}

private struct CalendarSelection: Identifiable {
    let id = UUID()
    let date: Date
}

struct CalendarDayKey: Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(dateComponents: DateComponents) {
        guard
            let year = dateComponents.year,
            let month = dateComponents.month,
            let day = dateComponents.day
        else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        guard let key = CalendarDayKey(dateComponents: components) else {
            preconditionFailure("Expected a valid year/month/day for calendar day key.")
        }
        self = key
    }

    var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}

extension CalendarDayKey: Hashable {
    nonisolated static func == (lhs: CalendarDayKey, rhs: CalendarDayKey) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
    }
}

struct DaySummarySheet: View {
    let date: Date
    let entries: [SetEntry]

    @Environment(QuickLogCoordinator.self) private var quickLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                Text(dayLabel)
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                    .accessibilityHidden(true)

                                CalendarSummaryMetricsView(
                                    metrics: CalendarSummaryMetrics(
                                        sets: entries.count,
                                        exercises: uniqueExerciseCount,
                                        averageRPE: averageRPE
                                    ),
                                    emphasis: .secondary
                                )
                                .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(dayOverviewAccessibilityLabel)
                            .accessibilityIdentifier("Calendar.DaySheet.Overview")

                            Button {
                                quickLog.open(prefillDate: date)
                                dismiss()
                            } label: {
                                HStack(spacing: MarbleSpacing.xxs) {
                                    Image(systemName: "plus")
                                        .accessibilityHidden(true)

                                    Text("Log Set for this day")
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                            }
                            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                            .accessibilityIdentifier("Calendar.DaySheet.LogSet")
                            .accessibilityLabel("Log Set for this day")
                        }
                        .padding(.vertical, 4)
                        .marbleRowInsets()
                    }

                    ProgressMediaSection(date: date)

                    if entries.isEmpty {
                        EmptyStateView(title: "No sets for this day", message: "Tap Log Set to add one here.", systemImage: "calendar")
                            .listRowSeparator(.hidden)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .marbleRowInsets()
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("Calendar.DaySheet.EmptyState")
                    } else {
                        Section {
                            ForEach(entries.sorted { $0.performedAt > $1.performedAt }) { entry in
                                NavigationLink {
                                    SetDetailView(entry: entry)
                                } label: {
                                    SetRowView(entry: entry)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
                                .accessibilityLabel(SetRowView.accessibilitySummary(for: entry))
                                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                                .marbleRowInsets()
                            }
                        } header: {
                            SectionHeaderView(title: "Sets")
                        }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .contentMargins(.top, MarbleSpacing.xs, for: .scrollContent)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("Calendar.DaySheet.List")
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var uniqueExerciseCount: Int {
        Set(entries.map { $0.exercise.id }).count
    }

    private var dayLabel: String {
        DateHelper.dayLabel(for: date)
    }

    private var dayOverviewAccessibilityLabel: String {
        let setLabel = pluralize(count: entries.count, singular: "set", plural: "sets")
        let exerciseLabel = pluralize(count: uniqueExerciseCount, singular: "exercise", plural: "exercises")
        return "\(dayLabel), \(entries.count) \(setLabel), \(uniqueExerciseCount) \(exerciseLabel), average RPE \(averageRPE)"
    }

    private func pluralize(count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    private var averageRPE: String {
        guard !entries.isEmpty else { return "-" }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        let avg = Double(total) / Double(entries.count)
        return String(format: "%.1f", avg)
    }
}

private struct CalendarSummaryMetrics {
    let sets: Int
    let exercises: Int
    let averageRPE: String

    var accessibilityLabel: String {
        "\(sets) \(setLabel), \(exercises) \(exerciseLabel), average RPE \(averageRPE)"
    }

    var setLabel: String {
        sets == 1 ? "set" : "sets"
    }

    var exerciseLabel: String {
        exercises == 1 ? "exercise" : "exercises"
    }
}

private struct CalendarSummaryMetricsView: View {
    enum Emphasis {
        case primary
        case secondary
    }

    let metrics: CalendarSummaryMetrics
    let emphasis: Emphasis

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    metricText("\(metrics.sets) \(metrics.setLabel)")
                    metricText("\(metrics.exercises) \(metrics.exerciseLabel)")
                    metricText("Avg RPE \(metrics.averageRPE)")
                }
            } else {
                HStack(spacing: MarbleSpacing.s) {
                    metricText("\(metrics.sets) \(metrics.setLabel)")
                    separator
                    metricText("\(metrics.exercises) \(metrics.exerciseLabel)")
                    separator
                    metricText("Avg RPE \(metrics.averageRPE)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metrics.accessibilityLabel)
    }

    private func metricText(_ value: String) -> some View {
        Text(value)
            .font(MarbleTypography.rowSubtitle)
            .foregroundStyle(textColor)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var separator: some View {
        Circle()
            .fill(Theme.secondaryTextColor(for: colorScheme))
            .frame(width: 3, height: 3)
            .accessibilityHidden(true)
    }

    private var textColor: Color {
        switch emphasis {
        case .primary:
            Theme.primaryTextColor(for: colorScheme)
        case .secondary:
            Theme.secondaryTextColor(for: colorScheme)
        }
    }
}

struct CalendarRepresentable: UIViewRepresentable {
    var activeDays: Set<CalendarDayKey>
    var visibleMonth: DateComponents
    var onSelect: (DateComponents?) -> Void
    var onVisibleMonthChange: (DateComponents) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.locale = Locale.current
        view.tintColor = .label
        view.clipsToBounds = true
        view.delegate = context.coordinator
        view.visibleDateComponents = visibleMonth
        view.accessibilityIdentifier = "Calendar.View"
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let screenWidth = uiView.window?.windowScene?.screen.bounds.width
        let fallbackWidth = uiView.bounds.width > 0 ? uiView.bounds.width : (screenWidth ?? 393)
        let width = max(0, proposal.width ?? fallbackWidth)
        let fittingSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let measured = uiView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = max(measured.height, uiView.intrinsicContentSize.height, 360)
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        let daysToReload = Set(context.coordinator.activeDays).union(activeDays)
        context.coordinator.activeDays = activeDays
        context.coordinator.visibleMonth = visibleMonth
        uiView.tintColor = .label
        uiView.reloadDecorations(
            forDateComponents: daysToReload.map(\.dateComponents),
            animated: true
        )
        if uiView.visibleDateComponents.year != visibleMonth.year || uiView.visibleDateComponents.month != visibleMonth.month {
            uiView.visibleDateComponents = visibleMonth
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelect: onSelect,
            onVisibleMonthChange: onVisibleMonthChange,
            activeDays: activeDays,
            visibleMonth: visibleMonth
        )
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        let onSelect: (DateComponents?) -> Void
        let onVisibleMonthChange: (DateComponents) -> Void
        var activeDays: Set<CalendarDayKey>
        var visibleMonth: DateComponents

        init(
            onSelect: @escaping (DateComponents?) -> Void,
            onVisibleMonthChange: @escaping (DateComponents) -> Void,
            activeDays: Set<CalendarDayKey>,
            visibleMonth: DateComponents
        ) {
            self.onSelect = onSelect
            self.onVisibleMonthChange = onVisibleMonthChange
            self.activeDays = activeDays
            self.visibleMonth = visibleMonth
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard
                let dayKey = CalendarDayKey(dateComponents: dateComponents),
                activeDays.contains(dayKey)
            else {
                return nil
            }
            return .image(CalendarDecoration.image(for: calendarView.traitCollection))
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            onSelect(dateComponents)
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            let updatedComponents = calendarView.visibleDateComponents
            guard updatedComponents.year != visibleMonth.year || updatedComponents.month != visibleMonth.month else {
                return
            }
            visibleMonth = updatedComponents
            onVisibleMonthChange(updatedComponents)
        }

        private func dateSelection(_ selection: UICalendarSelectionSingleDate, didDeselectDate dateComponents: DateComponents?) {
            onSelect(nil)
        }
    }
}

enum CalendarDecoration {
    private static let lightImage = dotImage(color: UIColor(white: ThemePalette.lightSecondaryText, alpha: 1.0))
    private static let darkImage = dotImage(color: UIColor(white: ThemePalette.darkSecondaryText, alpha: 1.0))

    static func image(for traits: UITraitCollection) -> UIImage {
        traits.userInterfaceStyle == .dark ? darkImage : lightImage
    }

    private static func dotImage(color: UIColor) -> UIImage {
        let canvasSize = CGSize(width: 18, height: 8)
        let dotSize: CGFloat = 6
        let dotRect = CGRect(
            x: (canvasSize.width - dotSize) / 2,
            y: (canvasSize.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: dotRect)
        }
    }
}
