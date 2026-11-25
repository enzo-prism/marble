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
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(systemName: "target", accent: accent, size: 26)
                Text("Weekly Goal")
                    .font(TrendsFont.section)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.Section.WeeklyGoal")

                Spacer(minLength: MarbleSpacing.s)

                targetMenu
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: MarbleSpacing.l) {
                    ring
                    progressStory
                }
                VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                    ring
                    progressStory
                }
            }

            TrendsStatRow(stats: [
                TrendsStat(
                    symbol: "flame.fill",
                    accent: TrendsPalette.sprint.color(for: colorScheme),
                    value: "\(snapshot.streakWeeks)",
                    unit: snapshot.streakWeeks == 1 ? "wk" : "wks",
                    label: "Streak"
                ),
                TrendsStat(
                    symbol: "shield.lefthalf.filled",
                    accent: TrendsPalette.strength.color(for: colorScheme),
                    value: "\(snapshot.flexTokens)",
                    unit: nil,
                    label: snapshot.flexTokens == 1 ? "Flex week" : "Flex weeks"
                ),
                TrendsStat(
                    symbol: "figure.strengthtraining.traditional",
                    accent: accent,
                    value: "\(snapshot.lifetimeActiveDays)",
                    unit: nil,
                    label: "Workouts"
                )
            ])
        }
        .trendsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.WeeklyGoal")
    }

    private var accent: Color { TrendsPalette.consistency.color(for: colorScheme) }

    private var ring: some View {
        TrendsGoalRing(done: snapshot.thisWeekSessions, target: snapshot.target, accent: accent)
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)
    }

    // One combined element (the house card pattern): the audit and
    // VoiceOver both treat the progress story as a single sentence
    // instead of judging each fragment's frame on its own.
    private var progressStory: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            HStack(alignment: .lastTextBaseline, spacing: MarbleSpacing.xxs) {
                Text("\(snapshot.thisWeekSessions) of \(snapshot.target)")
                    .font(TrendsFont.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Text("this week")
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            Text(stateLine)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.thisWeekSessions) of \(snapshot.target) sessions this week. \(stateLine)")
        .accessibilityIdentifier("Trends.WeeklyGoal.State")
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

    private var progressingCount: Int {
        assessments.filter { $0.verdict == .progressing }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(
                    systemName: "dumbbell.fill",
                    accent: TrendsPalette.strength.color(for: colorScheme),
                    size: 26
                )
                TrendsSectionHeader(
                    title: "Your Lifts",
                    takeaway: progressingCount > 0 ? "\(progressingCount) progressing" : nil,
                    takeawayGlyph: progressingCount > 0 ? "arrow.up.right" : nil,
                    accent: TrendsPalette.strength.color(for: colorScheme),
                    identifier: "Trends.Section.YourLifts"
                )
            }

            VStack(spacing: MarbleSpacing.s) {
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
        .trendsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.StrengthDashboard")
    }
}

private struct StrengthLiftRowView: View {
    let assessment: LifterCoaching.ProgressionAssessment
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var verdictColor: Color {
        TrendsPalette.verdictColor(assessment.verdict, scheme: colorScheme)
    }

    private var lineColor: Color {
        assessment.verdict == .progressing || assessment.verdict == .adapted
            ? verdictColor
            : TrendsPalette.strength.color(for: colorScheme)
    }

    var body: some View {
        Button {
            MarbleHaptics.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                // Name and e1RM share the top line and the verdict chip sits
                // beneath, so every row keeps the same shape whatever the
                // chip's length; large text stacks each pair instead.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                        nameText
                            .frame(maxWidth: .infinity, alignment: .leading)
                        valueLine
                    }
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        nameText
                        valueLine
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: MarbleSpacing.s) {
                        verdictChip
                        Spacer(minLength: 0)
                        estimateLabel
                    }
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        verdictChip
                        estimateLabel
                    }
                }

                if assessment.exposures.count > 1 {
                    sparkline
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 56 : 44)
                }
            }
            .padding(MarbleSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TrendsLayout.innerRadius + 2, style: .continuous)
                    .fill(Theme.backgroundColor(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.85))
            )
            .contentShape(RoundedRectangle(cornerRadius: TrendsLayout.innerRadius + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(assessment.exerciseName), \(verdictText), estimated one rep max \(weightText(assessment.latestDisplayValue)) \(assessment.displayUnit.symbol)")
        .accessibilityHint("Filters Trends to this exercise")
        .accessibilityIdentifier("Trends.Lift.\(assessment.exerciseName.replacingOccurrences(of: " ", with: ""))")
    }

    private var nameText: some View {
        Text(assessment.exerciseName)
            .font(MarbleTypography.rowTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var verdictChip: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.xxs) {
            Image(systemName: verdictSymbol)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(verdictColor)
            Text(verdictText)
                .font(MarbleTypography.rowMeta.weight(.medium))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MarbleSpacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                assessment.verdict == .holding || assessment.verdict == .building
                    ? Theme.chipFillColor(for: colorScheme)
                    : TrendsPalette.wash(verdictColor, scheme: colorScheme)
            )
        )
    }

    private var valueLine: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(weightText(assessment.latestDisplayValue))
                .font(TrendsFont.metric)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
            Text(assessment.displayUnit.symbol)
                .font(MarbleTypography.rowMeta.weight(.semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .fixedSize()
    }

    private var estimateLabel: some View {
        Text("est. 1RM")
            .font(MarbleTypography.smallLabel)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .fixedSize()
    }

    private var verdictSymbol: String {
        switch assessment.verdict {
        case .progressing: "arrow.up.right"
        case .holding: "equal"
        case .adapted: "arrow.triangle.2.circlepath"
        case .building: "circle.dashed"
        }
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
        let last = assessment.exposures.last
        let best = assessment.exposures.max { $0.e1RMKilograms < $1.e1RMKilograms }
        return Chart {
            ForEach(assessment.exposures) { exposure in
                AreaMark(
                    x: .value("Day", exposure.date),
                    yStart: .value("Floor", sparklineDomain.lowerBound),
                    yEnd: .value("e1RM", exposure.e1RMKilograms)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(TrendsPalette.areaGradient(lineColor))
            }
            ForEach(assessment.exposures) { exposure in
                LineMark(
                    x: .value("Day", exposure.date),
                    y: .value("e1RM", exposure.e1RMKilograms)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
            }
            if let best, best.id != last?.id {
                PointMark(x: .value("Day", best.date), y: .value("e1RM", best.e1RMKilograms))
                    .symbolSize(22)
                    .foregroundStyle(TrendsPalette.personalRecord.color(for: colorScheme))
            }
            if let last {
                PointMark(x: .value("Day", last.date), y: .value("e1RM", last.e1RMKilograms))
                    .symbol { TrendsEndpointDot(accent: lineColor, size: 8) }
            }
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
        let padding = max((maxValue - minValue) * 0.25, 0.5)
        return (minValue - padding) ... (maxValue + padding)
    }

    /// An estimate earns no decimals it can't back up: whole pounds, or the
    /// nearest half kilo ("215.83 lb" read as false precision).
    private func weightText(_ value: Double) -> String {
        let rounded = assessment.displayUnit == .kg ? (value * 2).rounded() / 2 : value.rounded()
        return Formatters.weight.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))"
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
            TrendsGlyphBadge(
                systemName: "arrow.up.right",
                accent: TrendsPalette.strength.color(for: colorScheme),
                size: 24
            )
        }
        .trendsCard(padding: MarbleSpacing.s)
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
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(systemName: "trophy.fill", accent: gold, size: 26, filled: true)
                TrendsSectionHeader(
                    title: "Records",
                    takeaway: events.count == 1 ? "1 PR" : "\(events.count) PRs",
                    takeawayGlyph: "sparkles",
                    accent: gold,
                    identifier: "Trends.Section.Records"
                )
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
                            .padding(.leading, 44)
                            .accessibilityHidden(true)
                    }
                }
            }

            if events.count > Self.displayCap {
                Text("+ \(events.count - Self.displayCap) more in this range")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .trendsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.PRFeed")
    }

    private var gold: Color { TrendsPalette.personalRecord.color(for: colorScheme) }
}

private struct PREventRowView: View {
    let event: LifterCoaching.PREvent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let gold = TrendsPalette.personalRecord.color(for: colorScheme)
        HStack(alignment: .center, spacing: MarbleSpacing.s) {
            ZStack {
                Circle()
                    .fill(TrendsPalette.wash(gold, scheme: colorScheme))
                Circle()
                    .strokeBorder(gold.opacity(0.55), lineWidth: 1)
                Image(systemName: "medal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(gold)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(event.exerciseName)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: MarbleSpacing.xxs) {
                    Text(event.badge.shortTitle)
                        .font(MarbleTypography.smallLabel.weight(.bold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(TrendsPalette.wash(gold, scheme: colorScheme)))
                    Text(event.setSummary)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DateHelper.dayLabel(for: event.date))
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize()
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

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: MarbleSpacing.xs)]

    var body: some View {
        let accent = TrendsPalette.strength.color(for: colorScheme)
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(systemName: "list.number", accent: accent, size: 26)
                TrendsSectionHeader(title: "Rep Records", identifier: "Trends.Section.RepRecords")
            }

            LazyVGrid(columns: columns, spacing: MarbleSpacing.xs) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Text(record.reps == 1 ? "1 rep" : "\(record.reps) reps")
                            .font(MarbleTypography.smallLabel.weight(.bold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TrendsPalette.wash(accent, scheme: colorScheme)))
                        Text(record.weightText)
                            .font(TrendsFont.metricSmall)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .monospacedDigit()
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MarbleSpacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: TrendsLayout.innerRadius, style: .continuous)
                            .fill(Theme.backgroundColor(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.85))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Best at \(record.reps) reps, \(record.weightText)")
                }
            }

            Text("Your heaviest set at each rep count — quiet records worth beating on lighter days.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .trendsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.RepRecords")
    }
}

// MARK: - Monthly report

struct MonthlyReportCardView: View {
    let report: MonthlyReport
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    /// Volume in the lifter's own unit, matching the report sheet.
    private var volumeText: String {
        MonthlyReportPhrasing.volumeText(
            kilograms: report.volumeKilograms,
            unit: WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
        )
    }

    var body: some View {
        Button {
            MarbleHaptics.selection()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack(alignment: .center, spacing: MarbleSpacing.xs) {
                    TrendsGlyphBadge(
                        systemName: "calendar",
                        accent: TrendsPalette.consistency.color(for: colorScheme),
                        size: 26
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reportTitle)
                            .font(TrendsFont.section)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        if let comparisonLabel = report.comparisonLabel {
                            Text(comparisonLabel)
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: MarbleSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }

                // Three columns at standard sizes; at accessibility sizes the
                // columns would hyphenate labels and split values, so each
                // metric becomes its own label/value row (HIG: reduce columns).
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        ForEach(metrics, id: \.label) { metric in
                            metricRow(metric)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: MarbleSpacing.xs) {
                        ForEach(metrics, id: \.label) { metric in
                            metricTile(metric)
                        }
                    }
                }
            }
            .trendsCard(padding: MarbleSpacing.m)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the full report")
        .accessibilityIdentifier("Trends.MonthlyReport")
    }

    private struct Metric {
        let value: String
        let label: String
        let delta: String?
    }

    private var metrics: [Metric] {
        [
            Metric(value: "\(report.sessions)", label: report.sessions == 1 ? "Session" : "Sessions", delta: report.sessionsDelta.map(deltaText)),
            Metric(value: volumeText, label: "Volume", delta: report.volumeDeltaPercent.map { deltaPercentText($0) }),
            Metric(value: "\(report.prCount)", label: report.prCount == 1 ? "PR" : "PRs", delta: report.prDelta.map(deltaText))
        ]
    }

    private var reportTitle: String {
        report.isMonthToDate ? "\(report.monthLabel) so far" : "\(report.monthLabel) report"
    }

    private func metricTile(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(MarbleTypography.rowMeta.weight(.medium))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(1)
            Text(metric.value)
                .font(TrendsFont.metricSmall)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let delta = metric.delta {
                Text(delta)
                    .font(MarbleTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TrendsLayout.innerRadius, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 1))
        )
    }

    private func metricRow(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(MarbleTypography.rowMeta.weight(.medium))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                Text(metric.value)
                    .font(TrendsFont.metricSmall)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .monospacedDigit()
                if let delta = metric.delta {
                    Text(delta)
                        .font(MarbleTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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
            "volume \(volumeText)",
            "\(report.prCount) personal records"
        ]
        if let comparisonLabel = report.comparisonLabel {
            parts.append(comparisonLabel)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Goal ring

/// One arc segment per target session; completed segments fill with the
/// consistency accent (gold once the target is beaten) and sweep in on
/// appear. The count sits in the middle.
struct TrendsGoalRing: View {
    let done: Int
    let target: Int
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: Double = trendsInitiallyRevealed() ? 1 : 0
    @State private var isRevealed = trendsInitiallyRevealed()

    var body: some View {
        let segments = max(target, 1)
        let gap = segments > 1 ? 0.018 : 0
        let fill = done > target ? TrendsPalette.personalRecord.color(for: colorScheme) : accent
        ZStack {
            ZStack {
                ForEach(0..<segments, id: \.self) { index in
                let start = Double(index) / Double(segments) + gap
                let end = Double(index + 1) / Double(segments) - gap
                Circle()
                    .trim(from: start, to: end)
                    .stroke(Theme.chipFillColor(for: colorScheme), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                if index < done {
                    Circle()
                        .trim(from: start, to: start + (end - start) * segmentProgress(index, of: segments))
                        .stroke(
                            AngularGradient(colors: [fill.opacity(0.75), fill], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                }
                }
            }
            .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(done)")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("of \(target)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(14)
        }
        .padding(5)
        .trendsReveal($isRevealed)
        .onChange(of: isRevealed) { _, revealed in
            guard revealed else { return }
            withAnimation(.easeOut(duration: 0.8)) { progress = 1 }
        }
        .onAppear { if isRevealed { progress = 1 } }
    }

    /// Segments fill one after another as `progress` runs 0 → 1.
    private func segmentProgress(_ index: Int, of count: Int) -> Double {
        let filled = Double(min(done, count))
        guard filled > 0 else { return 0 }
        let local = progress * filled - Double(index)
        return min(max(local, 0), 1)
    }
}
