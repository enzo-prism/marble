import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @EnvironmentObject private var tabSelection: TabSelection
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var selectedDay: CalendarSelection?
    @State private var selectedDate: Date?
    @State private var visibleMonth = Calendar.current.dateComponents([.year, .month], from: AppEnvironment.now)

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                if TestHooks.isUITesting {
                    testControlsRow
                }

                calendarHeader

                Button("Log Set") {
                    let targetDate = selectedDate ?? AppEnvironment.now
                    quickLog.open(prefillDate: targetDate)
                }
                .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                .accessibilityIdentifier("Calendar.LogSet")

                CalendarRepresentable(
                    activeDays: activeWorkoutDays,
                    visibleMonth: visibleMonth,
                    onSelect: { components in
                        guard let components, let date = calendar.date(from: components) else {
                            selectedDay = nil
                            selectedDate = nil
                            return
                        }
                        selectedDate = date
                        selectedDay = CalendarSelection(date: date)
                    },
                    onVisibleMonthChange: { components in
                        visibleMonth = components
                    }
                )
                .frame(maxHeight: 360)
                .accessibilityIdentifier("Calendar.View")

                Spacer()
            }
            .padding(.horizontal, MarbleLayout.pagePadding)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
            .onAppear {
                ensureTestDaySheetVisible()
            }
            .onChange(of: tabSelection.selected) { _, selection in
                if selection == .calendar {
                    ensureTestDaySheetVisible()
                }
            }
            .sheet(item: $selectedDay) { selection in
                DaySummarySheet(date: selection.date, entries: entriesForDay(selection.date))
                    .environmentObject(quickLog)
            }
        }
    }

    private var activeWorkoutDays: Set<CalendarDayKey> {
        Set(entries.map { entry in
            CalendarDayKey(date: entry.performedAt, calendar: calendar)
        })
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
        selectedDay = CalendarSelection(date: targetDate)
    }

    private func ensureTestDaySheetVisible() {
        guard TestHooks.isUITesting, let mode = TestHooks.calendarTestDay else { return }
        selectedDay = nil
        DispatchQueue.main.async {
            openTestDay(mode: mode)
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

    private var calendarHeader: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                    headerTitle
                    Spacer(minLength: MarbleSpacing.s)
                    streakBadge
                }
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    headerTitle
                    streakBadge
                }
            }

            Text(daySummaryLine)
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

    private var streakBadge: some View {
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: "flame.fill")
                .accessibilityHidden(true)
            Text(streakLabel)
        }
        .font(MarbleTypography.smallLabel)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xxs)
        .background(
            Capsule()
                .fill(Theme.chipFillColor(for: colorScheme))
        )
        .overlay(
            Capsule()
                .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
        )
        .accessibilityLabel(streakLabel)
        .accessibilityIdentifier("Calendar.Header.Streak")
    }

    private var headerDate: Date {
        selectedDate ?? AppEnvironment.now
    }

    private var daySummaryLine: String {
        let dayEntries = entriesForDay(headerDate)
        let setCount = dayEntries.count
        let exerciseCount = Set(dayEntries.map { $0.exercise.id }).count
        let avgRPE = averageRPE(for: dayEntries)
        let setLabel = pluralize(count: setCount, singular: "set", plural: "sets")
        let exerciseLabel = pluralize(count: exerciseCount, singular: "exercise", plural: "exercises")
        return "\(setCount) \(setLabel) · \(exerciseCount) \(exerciseLabel) · Avg RPE \(avgRPE)"
    }

    private var streakLabel: String {
        let count = currentStreak
        let dayLabel = pluralize(count: count, singular: "day", plural: "days")
        return "Streak \(count) \(dayLabel)"
    }

    private var currentStreak: Int {
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.performedAt) })
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(DateHelper.dayLabel(for: date))
                            .font(MarbleTypography.screenTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text("\(entries.count) sets · \(uniqueExerciseCount) exercises · Avg RPE \(averageRPE)")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        Button("Log Set for this day") {
                            quickLog.open(prefillDate: date)
                            dismiss()
                        }
                        .buttonStyle(MarbleActionButtonStyle())
                        .accessibilityIdentifier("Calendar.DaySheet.LogSet")
                    }
                    .padding(.vertical, 4)
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    EmptyStateView(title: "No sets for this day", message: "Tap Log Set to add one here.", systemImage: "calendar")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
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
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Calendar.DaySheet.List")
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var uniqueExerciseCount: Int {
        Set(entries.map { $0.exercise.id }).count
    }

    private var averageRPE: String {
        guard !entries.isEmpty else { return "-" }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        let avg = Double(total) / Double(entries.count)
        return String(format: "%.1f", avg)
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
