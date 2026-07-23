import SwiftUI
import Charts
import TipKit

// The coaching-layer Trends sections: weekly goal, strength dashboard,
// monthly report, PR feed, and rep records. Like the lifter-analytics
// sections these are glanceable summaries — the interpretation lives in
// plain words next to each chart, per the HIG's charting guidance.

extension TrendsPalette {
    /// Verdict dot for a progressing lift; reuses the strength accent.
    static func verdictColor(
        _ verdict: LifterCoaching.ProgressionVerdict,
        scheme: ColorScheme
    ) -> Color {
        switch verdict {
        case .progressing:
            return TrendsPalette.strength.color(for: scheme)
        case .adapted:
            return TrendsPalette.effort.color(for: scheme)
        case .holding, .building:
            return Theme.secondaryTextColor(for: scheme)
        }
    }
}

// MARK: - Weekly goal

struct ConsistencyGoalCardView: View {
    let snapshot: TrainingConsistency.Snapshot
    @Binding var weeklyTarget: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Goal")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.Section.WeeklyGoal")

                Spacer(minLength: MarbleSpacing.s)

                targetMenu
            }

            // One combined element (the house card pattern): the audit and
            // VoiceOver both treat the progress story as a single sentence
            // instead of judging each fragment's frame on its own.
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack(spacing: MarbleSpacing.s) {
                    sessionDots

                    Text("\(snapshot.thisWeekSessions) of \(snapshot.target) this week")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }

                Text(stateLine)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.thisWeekSessions) of \(snapshot.target) sessions this week. \(stateLine)")
            .accessibilityIdentifier("Trends.WeeklyGoal.State")

            HStack(spacing: MarbleSpacing.m) {
                statCell(value: "\(snapshot.streakWeeks)", label: "week streak")
                statCell(value: "\(snapshot.flexTokens)", label: snapshot.flexTokens == 1 ? "flex week banked" : "flex weeks banked")
                statCell(value: "\(snapshot.lifetimeActiveDays)", label: "workouts logged")
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.WeeklyGoal")
    }

    private var targetMenu: some View {
        Menu {
            ForEach(1...7, id: \.self) { target in
                Button {
                    weeklyTarget = target
                    MarbleHaptics.selection()
                } label: {
                    if target == snapshot.target {
                        Label(targetLabel(target), systemImage: "checkmark")
                    } else {
                        Text(targetLabel(target))
                    }
                }
            }
        } label: {
            HStack(spacing: MarbleSpacing.xxs) {
                Text("\(snapshot.target)×/wk")
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            // The visible chip is small; the tap target must not be.
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Weekly session target")
        .accessibilityValue("\(snapshot.target) sessions per week")
        .accessibilityIdentifier("Trends.WeeklyGoal.Target")
    }

    private func targetLabel(_ target: Int) -> String {
        target == 1 ? "1 session a week" : "\(target) sessions a week"
    }

    private var sessionDots: some View {
        HStack(spacing: MarbleSpacing.xxs) {
            ForEach(0..<snapshot.target, id: \.self) { index in
                Circle()
                    .fill(
                        index < snapshot.thisWeekSessions
                            ? TrendsPalette.consistency.color(for: colorScheme)
                            : Theme.subtleDividerColor(for: colorScheme)
                    )
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func statCell(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
            Text(value)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
            Text(label)
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
    }

    /// Forgiveness-first copy: the comeback is congratulated, the risk state
    /// names what's left, and nothing here ever shames a miss.
    private var stateLine: String {
        switch snapshot.state {
        case .fresh:
            return "Log a set to start your first week."
        case .hit:
            return "Target hit — this week is banked."
        case .comeback:
            return "Back on track — showing up again is the hard part."
        case .atRisk:
            let needed = max(snapshot.target - snapshot.thisWeekSessions, 0)
            return needed == 1
                ? "1 more session keeps the week — still doable."
                : "\(needed) more sessions to keep the week — every remaining day counts."
        case .inProgress:
            let needed = max(snapshot.target - snapshot.thisWeekSessions, 0)
            return needed == 1
                ? "1 more session this week."
                : "\(needed) more sessions this week."
        }
    }

}

// MARK: - Strength dashboard

struct StrengthDashboardView: View {
    let assessments: [LifterCoaching.ProgressionAssessment]
    let onSelect: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Your Lifts")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.YourLifts")

            VStack(spacing: MarbleSpacing.xs) {
                ForEach(assessments) { assessment in
                    StrengthLiftRowView(assessment: assessment) {
                        // Tapping a lift row is organic discovery of the
                        // tappable coaching cards; the tip (anchored on the
                        // Focus card) must never show after this.
                        CoachingCardsTip().invalidate(reason: .actionPerformed)
                        onSelect(assessment.exerciseID)
                    }
                }
            }

            Text("Estimated 1RM trend across each lift's last \(LifterCoaching.progressionWindow) sessions, compared at matched effort. Tap a lift for the full picture.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.StrengthDashboard")
    }
}

private struct StrengthLiftRowView: View {
    let assessment: LifterCoaching.ProgressionAssessment
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            MarbleHaptics.selection()
            onTap()
        } label: {
            HStack(spacing: MarbleSpacing.s) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(assessment.exerciseName)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
                        Circle()
                            .fill(TrendsPalette.verdictColor(assessment.verdict, scheme: colorScheme))
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(verdictText)
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                sparkline
                    .frame(width: 72, height: 32)

                VStack(alignment: .trailing, spacing: MarbleSpacing.xxxs) {
                    Text("\(weightText(assessment.latestDisplayValue)) \(assessment.displayUnit.symbol)")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .monospacedDigit()
                    Text("e1RM")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)
                }
            }
            .padding(MarbleSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(assessment.exerciseName), \(verdictText), estimated one rep max \(weightText(assessment.latestDisplayValue)) \(assessment.displayUnit.symbol)")
        .accessibilityHint("Filters Trends to this exercise")
        .accessibilityIdentifier("Trends.Lift.\(assessment.exerciseName.replacingOccurrences(of: " ", with: ""))")
    }

    /// Evidence-first, never a verdict on the person: "adapted" reads as
    /// information ("that usually means you've adapted"), not "unproductive".
    private var verdictText: String {
        let sessions = assessment.exposures.count
        switch assessment.verdict {
        case .progressing:
            return String(format: "Progressing · %+.1f%% over %d sessions", assessment.percentChange, sessions)
        case .holding:
            return "Holding steady"
        case .adapted:
            return "Flat \(sessions) sessions — likely adapted"
        case .building:
            return "Building baseline · \(sessions) of \(LifterCoaching.minimumExposuresForVerdict) sessions"
        }
    }

    private var sparkline: some View {
        Chart(assessment.exposures) { exposure in
            LineMark(
                x: .value("Day", exposure.date),
                y: .value("e1RM", exposure.e1RMKilograms)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(TrendsPalette.strength.color(for: colorScheme))
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: sparklineDomain)
        .accessibilityHidden(true)
    }

    private var sparklineDomain: ClosedRange<Double> {
        let values = assessment.exposures.map(\.e1RMKilograms)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * 0.2, 0.5)
        return (minValue - padding) ... (maxValue + padding)
    }

    private func weightText(_ value: Double) -> String {
        Formatters.weight.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Double-progression hint

struct DoubleProgressionHintView: View {
    let hint: LifterCoaching.DoubleProgressionHint

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text("\(Text(hint.evidence).fontWeight(.semibold)) — \(hint.suggestion).")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TrendsPalette.strength.color(for: colorScheme))
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hint.evidence), \(hint.suggestion)")
        .accessibilityIdentifier("Trends.DoubleProgression")
    }
}

// MARK: - PR feed

struct PRFeedSectionView: View {
    let events: [LifterCoaching.PREvent]
    /// How many events the section lists before collapsing into a count.
    static let displayCap = 5

    @Environment(\.colorScheme) private var colorScheme

    /// Shown once on the section header. The feed is display-only — there is no
    /// control to hang `.actionPerformed` on — so "using the feature" is having
    /// seen the section: invalidate when it leaves the screen, and the tip
    /// never shows again anywhere (the `MarbleTips` contract, adapted).
    private let prFeedTip = PRFeedTip()

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Records")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.Section.Records")

                Spacer(minLength: MarbleSpacing.s)

                Text(events.count == 1 ? "1 PR" : "\(events.count) PRs")
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .monospacedDigit()
            }
            .popoverTip(prFeedTip)
            .onDisappear {
                prFeedTip.invalidate(reason: .actionPerformed)
            }

            VStack(spacing: 0) {
                ForEach(Array(events.prefix(Self.displayCap).enumerated()), id: \.element.id) { index, event in
                    PREventRowView(event: event)
                    if index < min(events.count, Self.displayCap) - 1 {
                        Divider()
                            .overlay(Theme.subtleDividerColor(for: colorScheme))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xxs)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)

            if events.count > Self.displayCap {
                Text("+ \(events.count - Self.displayCap) more in this range")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.PRFeed")
    }
}

private struct PREventRowView: View {
    let event: LifterCoaching.PREvent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(event.exerciseName)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(1)
                Text("\(event.badge.shortTitle) · \(event.setSummary)")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DateHelper.dayLabel(for: event.date))
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .padding(.vertical, MarbleSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.exerciseName), \(event.badge.accessibilityDescription), \(event.setSummary), \(DateHelper.dayLabel(for: event.date))")
    }
}

// MARK: - Rep records (quiet table)

struct RepRecordsSectionView: View {
    let records: [LifterCoaching.RepRecord]

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: MarbleSpacing.xs)]

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Rep Records")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.RepRecords")

            LazyVGrid(columns: columns, spacing: MarbleSpacing.xs) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                        Text(record.reps == 1 ? "1 rep" : "\(record.reps) reps")
                            .font(MarbleTypography.smallLabel)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .textCase(.uppercase)
                        Text(record.weightText)
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .monospacedDigit()
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MarbleSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Best at \(record.reps) reps, \(record.weightText)")
                }
            }

            Text("Your heaviest set at each rep count — quiet records worth beating on lighter days.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.RepRecords")
    }
}

// MARK: - Monthly report

struct MonthlyReportCardView: View {
    let report: MonthlyReport
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            MarbleHaptics.selection()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reportTitle)
                        .font(MarbleTypography.sectionTitle)
                        .foregroundColor(Theme.primaryTextColor(for: colorScheme))

                    Spacer(minLength: MarbleSpacing.s)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }

                HStack(spacing: MarbleSpacing.m) {
                    reportMetric(value: "\(report.sessions)", label: "sessions", delta: report.sessionsDelta.map(deltaText))
                    reportMetric(value: MonthlyReportPhrasing.volumeText(kilograms: report.volumeKilograms), label: "volume", delta: report.volumeDeltaPercent.map { deltaPercentText($0) })
                    reportMetric(value: "\(report.prCount)", label: report.prCount == 1 ? "PR" : "PRs", delta: report.prDelta.map(deltaText))
                }

                if let comparisonLabel = report.comparisonLabel {
                    Text(comparisonLabel)
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .padding(MarbleSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the full report")
        .accessibilityIdentifier("Trends.MonthlyReport")
    }

    private var reportTitle: String {
        report.isMonthToDate ? "\(report.monthLabel) — so far" : "\(report.monthLabel) Report"
    }

    private func reportMetric(value: String, label: String, delta: String?) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .textCase(.uppercase)
            if let delta {
                Text(delta)
                    .font(MarbleTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaText(_ delta: Int) -> String {
        delta == 0 ? "even" : String(format: "%+d", delta)
    }

    private func deltaPercentText(_ delta: Double) -> String {
        String(format: "%+.0f%%", delta)
    }

    private var accessibilityText: String {
        var parts = [
            reportTitle,
            "\(report.sessions) sessions",
            "volume \(MonthlyReportPhrasing.volumeText(kilograms: report.volumeKilograms))",
            "\(report.prCount) personal records"
        ]
        if let comparisonLabel = report.comparisonLabel {
            parts.append(comparisonLabel)
        }
        return parts.joined(separator: ", ")
    }
}
