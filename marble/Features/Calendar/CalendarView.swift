import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \ProgressMediaAttachment.createdAt, order: .reverse)
    private var progressMediaAttachments: [ProgressMediaAttachment]

    @State private var selectedDay: CalendarSelection?
    @State private var visibleMonth = Calendar.current.dateComponents([.year, .month], from: AppEnvironment.now)
    @State private var didOpenRequestedTestDay = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: MarbleSpacing.s) {
                if TestHooks.isUITesting && !TestHooks.isAccessibilityAudit {
                    testControlsRow
                }

                CalendarRepresentable(
                    activeDays: activeDays,
                    visibleMonth: visibleMonth,
                    onSelect: { components in
                        guard let components, let date = calendar.date(from: components) else {
                            selectedDay = nil
                            return
                        }
                        presentDaySheet(for: date)
                    },
                    onVisibleMonthChange: { components in
                        visibleMonth = components
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .accessibilityIdentifier("Calendar.View")
            }
            .padding(.horizontal, MarbleLayout.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        SplitView()
                    } label: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .accessibilityLabel("Split")
                    .accessibilityIdentifier("Calendar.Split")

                    AddSetToolbarButton()
                }
            }
        }
        .sheet(item: $selectedDay) { selectedDay in
            DaySummarySheet(date: selectedDay.date, entries: entriesForDay(selectedDay.date))
                .environmentObject(quickLog)
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .onAppear {
            openRequestedTestDayIfNeeded()
        }
    }

    private var activeWorkoutDays: Set<CalendarDayKey> {
        Set(entries.map { entry in
            CalendarDayKey(date: entry.performedAt, calendar: calendar)
        })
    }

    private var activeProgressMediaDays: Set<CalendarDayKey> {
        Set(progressMediaAttachments.map { attachment in
            CalendarDayKey(date: attachment.attachedToDate, calendar: calendar)
        })
    }

    private var activeDays: Set<CalendarDayKey> {
        activeWorkoutDays.union(activeProgressMediaDays)
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

    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if !dynamicTypeSize.isAccessibilitySize && !entries.isEmpty {
                        Section {
                            Text(dayOverviewLine)
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                                .marbleRowInsets()
                                .accessibilityLabel(dayOverviewAccessibilityLabel)
                                .accessibilityIdentifier("Calendar.DaySheet.Overview")
                        }
                    }

                    if entries.isEmpty {
                        EmptyStateView(title: "No sets for this day", message: "Use + to log this day.", systemImage: "calendar")
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

                    ProgressMediaSection(date: date)
                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .contentMargins(.top, MarbleSpacing.xs, for: .scrollContent)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("Calendar.DaySheet.List")
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: logSetForDay) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Calendar.DaySheet.LogSet")
                    .accessibilityLabel("Log Set for this day")
                }
            }
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

    private var dayOverviewLine: String {
        let setLabel = pluralize(count: entries.count, singular: "set", plural: "sets")
        let exerciseLabel = pluralize(count: uniqueExerciseCount, singular: "exercise", plural: "exercises")
        return "\(entries.count) \(setLabel) · \(uniqueExerciseCount) \(exerciseLabel) · Avg RPE \(averageRPE)"
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

    private func logSetForDay() {
        quickLog.open(prefillDate: date)
        dismiss()
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
        view.delegate = context.coordinator
        view.visibleDateComponents = visibleMonth
        view.accessibilityIdentifier = "Calendar.View"
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        return view
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
