import SwiftUI

enum TrendsSheetDestination: Identifiable {
    case day(Date)
    case week(Date)
    case supplementDay(Date)

    var id: String {
        switch self {
        case .day(let date):
            return "day-\(date.timeIntervalSince1970)"
        case .week(let date):
            return "week-\(date.timeIntervalSince1970)"
        case .supplementDay(let date):
            return "supplement-day-\(date.timeIntervalSince1970)"
        }
    }
}

struct DayDetailsSheet: View {
    let date: Date
    let entries: [SetEntry]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text(DateHelper.dayLabel(for: date))
                            .font(MarbleTypography.screenTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text(summaryText)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xxs)
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    EmptyStateView(title: "No sets", message: "Log a set to start tracking this day.", systemImage: "calendar")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("Trends.DaySheet.EmptyState")
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
            .accessibilityIdentifier("Trends.DaySheet.List")
            .navigationTitle("Day Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var summaryText: String {
        let uniqueExercises = Set(entries.map { $0.exercise.id }).count
        let averageRPE: String = {
            guard !entries.isEmpty else { return "-" }
            let total = entries.reduce(0) { $0 + $1.difficulty }
            let avg = Double(total) / Double(entries.count)
            return String(format: "%.1f", avg)
        }()
        return "\(entries.count) sets · \(uniqueExercises) exercises · Avg RPE \(averageRPE)"
    }
}

struct WeekDetailsSheet: View {
    let weekStart: Date
    let weekEnd: Date
    let entries: [SetEntry]

    @Environment(\.colorScheme) private var colorScheme

    private var groupedEntries: [(date: Date, entries: [SetEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.performedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            let dayEntries = grouped[day]?.sorted { $0.performedAt > $1.performedAt } ?? []
            return (day, dayEntries)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text(TrendsDateHelper.weekLabel(start: weekStart, end: weekEnd))
                            .font(MarbleTypography.screenTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text(summaryText)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xxs)
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    EmptyStateView(title: "No sets", message: "Log sets to start tracking this week.", systemImage: "calendar")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("Trends.WeekSheet.EmptyState")
                } else {
                    ForEach(groupedEntries, id: \.date) { dayGroup in
                        Section {
                            ForEach(dayGroup.entries) { entry in
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
                            SectionHeaderView(title: DateHelper.dayLabel(for: dayGroup.date))
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Trends.WeekSheet.List")
            .navigationTitle("Week Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var summaryText: String {
        let uniqueExercises = Set(entries.map { $0.exercise.id }).count
        let averageRPE: String = {
            guard !entries.isEmpty else { return "-" }
            let total = entries.reduce(0) { $0 + $1.difficulty }
            let avg = Double(total) / Double(entries.count)
            return String(format: "%.1f", avg)
        }()
        return "\(entries.count) sets · \(uniqueExercises) exercises · Avg RPE \(averageRPE)"
    }
}

struct SupplementDayDetailsSheet: View {
    let date: Date
    let entries: [SupplementEntry]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text(DateHelper.dayLabel(for: date))
                            .font(MarbleTypography.screenTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text(summaryText)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xxs)
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    EmptyStateView(title: "No logs", message: "Log supplements to track this day.", systemImage: "pills")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("Trends.SupplementDaySheet.EmptyState")
                } else {
                    Section {
                        ForEach(entries.sorted { $0.takenAt > $1.takenAt }) { entry in
                            NavigationLink {
                                SupplementDetailView(entry: entry)
                            } label: {
                                SupplementRowView(entry: entry)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("SupplementRow.\(entry.id.uuidString)")
                            .accessibilityLabel(SupplementRowView.accessibilityLabel(for: entry))
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .marbleRowInsets()
                        }
                    } header: {
                        SectionHeaderView(title: "Logs")
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Trends.SupplementDaySheet.List")
            .navigationTitle("Supplement Logs")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var summaryText: String {
        let uniqueTypes = Set(entries.map { $0.type.id }).count
        return "\(entries.count) logs · \(uniqueTypes) supplements"
    }
}
