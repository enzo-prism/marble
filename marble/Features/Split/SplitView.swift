import SwiftUI
import SwiftData

struct SplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(filter: #Predicate<SplitPlan> { $0.isActive == true }, sort: \SplitPlan.updatedAt, order: .reverse)
    private var plans: [SplitPlan]

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlan {
                    splitList(plan: plan)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
        }
    }

    private var activePlan: SplitPlan? {
        plans.first
    }

    private func splitList(plan: SplitPlan) -> some View {
        List {
            Section {
                ForEach(orderedDays(from: plan)) { day in
                    NavigationLink {
                        SplitDayEditorView(day: day)
                    } label: {
                        SplitDayRowView(day: day)
                    }
                    .marbleRowInsets()
                    .accessibilityIdentifier("Split.Day.\(day.weekday.displayName)")
                }
            } header: {
                SectionHeaderView(title: "Weekly Plan")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Split.List")
    }

    private var emptyState: some View {
        VStack(spacing: MarbleSpacing.m) {
            EmptyStateView(
                title: "No split yet",
                message: "Create a 7-day plan to map your workouts.",
                systemImage: "calendar.badge.plus"
            )
            Button("Create Split") {
                SeedData.ensureSplitPlan(in: modelContext)
            }
            .buttonStyle(MarbleActionButtonStyle())
            .accessibilityIdentifier("Split.Create")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Split.EmptyState")
    }

    private func orderedDays(from plan: SplitPlan) -> [SplitDay] {
        plan.days.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.weekday.rawValue < $1.weekday.rawValue
        }
    }
}

private struct SplitDayRowView: View {
    let day: SplitDay

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
            Text(day.weekday.displayName)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Text(day.title.isEmpty ? "Rest" : day.title)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Split.DayTitle.\(day.weekday.displayName)")

            if let notes = day.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [day.weekday.displayName]
        let title = day.title.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(title.isEmpty ? "Rest" : title)
        if let notes = day.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: ", ")
    }
}
