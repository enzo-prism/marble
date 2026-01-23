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
                        ExerciseProgressChart(points: points) { date in
                            sheetDestination = .day(date)
                        }
                        .accessibilityIdentifier("ExerciseProgress.Chart")
                    }
                }
                .padding(MarbleLayout.pagePadding)
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .day(let date):
                DayDetailsSheet(date: date, entries: entriesForDay(date))
            case .week:
                EmptyView()
            }
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

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(Theme.dividerColor(for: colorScheme))
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
    let onViewSets: (Date) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Theme.dividerColor(for: colorScheme))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected Day", selectedPoint.date))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) {
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

                PointMark(
                    x: .value("Selected Day", selectedPoint.date),
                    y: .value("Score", selectedPoint.score)
                )
                .symbolSize(70)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }
        }
        .frame(height: 180)
        .chartXSelection(value: $selectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress chart")
        .accessibilityValue(progressAccessibilityValue)
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
}
