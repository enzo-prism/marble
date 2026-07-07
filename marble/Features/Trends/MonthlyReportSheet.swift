import SwiftUI

/// The full monthly report: totals, month-over-month deltas, muscle focus,
/// and short insights. Insights are phrased on device (Apple Intelligence
/// when available, deterministic wording otherwise); the numbers on this
/// screen never depend on the model.
struct MonthlyReportSheet: View {
    let report: MonthlyReport

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var insights: [String] = []
    @State private var isLoadingInsights = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    statsGrid

                    if let comparisonLabel = report.comparisonLabel {
                        Text(comparisonLabel)
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }

                    if !report.topMuscleGroups.isEmpty {
                        muscleFocusSection
                    }

                    insightsSection
                }
                .padding(MarbleLayout.pagePadding)
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle(report.isMonthToDate ? "\(report.monthLabel) — so far" : report.monthLabel)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("Trends.MonthlyReportSheet.Done")
                }
            }
        }
        .task {
            insights = await TrainingInsights.insights(for: report)
            isLoadingInsights = false
        }
    }

    private var statsGrid: some View {
        let cells: [(String, String, String?)] = [
            ("Sessions", "\(report.sessions)", report.sessionsDelta.map { String(format: "%+d", $0) }),
            ("Sets", "\(report.sets)", nil),
            ("Volume", MonthlyReportPhrasing.volumeText(kilograms: report.volumeKilograms), report.volumeDeltaPercent.map { String(format: "%+.0f%%", $0) }),
            (report.prCount == 1 ? "Record" : "Records", "\(report.prCount)", report.prDelta.map { String(format: "%+d", $0) })
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MarbleSpacing.xs) {
            ForEach(cells, id: \.0) { title, value, delta in
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(title)
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
                        Text(value)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .monospacedDigit()
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        if let delta {
                            Text(delta)
                                .font(MarbleTypography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                }
                .padding(MarbleSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) \(value)\(delta.map { ", \($0)" } ?? "")")
            }
        }
        .accessibilityIdentifier("Trends.MonthlyReportSheet.Stats")
    }

    private var muscleFocusSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Most Trained")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))

            VStack(spacing: 0) {
                ForEach(Array(report.topMuscleGroups.enumerated()), id: \.element.id) { index, focus in
                    HStack {
                        Text(focus.category.displayName)
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Spacer()
                        Text(focus.sets == 1 ? "1 set" : "\(focus.sets) sets")
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .monospacedDigit()
                    }
                    .padding(.vertical, MarbleSpacing.xs)
                    .accessibilityElement(children: .combine)

                    if index < report.topMuscleGroups.count - 1 {
                        Divider()
                            .overlay(Theme.subtleDividerColor(for: colorScheme))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xxs)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Insights")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))

            if isLoadingInsights {
                HStack(spacing: MarbleSpacing.s) {
                    ProgressView()
                    Text("Reading your month…")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                .padding(MarbleSpacing.s)
            } else {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    ForEach(insights, id: \.self) { insight in
                        Label {
                            Text(insight)
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                }
                .padding(MarbleSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
            }

            Text("Computed privately on this iPhone. Insights phrase the stats above — the numbers come first.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("Trends.MonthlyReportSheet.Insights")
    }
}
