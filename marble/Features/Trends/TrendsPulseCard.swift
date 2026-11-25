import SwiftUI
import Charts

extension TrendRange {
    /// Sentence-case span name for headers ("Last 30 days").
    var spanTitle: String {
        switch self {
        case .sevenDays: "Last 7 days"
        case .thirtyDays: "Last 30 days"
        case .ninetyDays: "Last 90 days"
        case .oneYear: "Past year"
        case .all: "All time"
        }
    }

    /// The window a delta is measured against ("previous 30 days").
    var comparisonTitle: String {
        switch self {
        case .sevenDays: "previous 7 days"
        case .thirtyDays: "previous 30 days"
        case .ninetyDays: "previous 90 days"
        case .oneYear: "year before"
        case .all: "previous period"
        }
    }
}

/// The hero of Progress Details: one big number for the range, its change
/// against the previous window, the training rhythm as a mini bar chart, and
/// a grid of supporting tiles. Replaces the old three-up summary strip and
/// keeps its `Trends.Summary` / `Trends.SummaryMetric.*` identifiers.
struct TrendsPulseCard: View {
    let derived: TrendsDerivedData
    let range: TrendRange
    let displayWeightUnit: WeightUnit
    let supplementFilterName: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = trendsInitiallyRevealed()

    private var setCount: Int { derived.filteredEntries.count }
    private var prCount: Int { derived.prEvents.count }
    private var consistencyAccent: Color { TrendsPalette.consistency.color(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            eyebrow
            headline
            if derived.consistencySummaries.count > 1, setCount > 0 {
                rhythm
            }
            tiles
        }
        .trendsCard(padding: MarbleSpacing.l)
        .overlay(alignment: .topTrailing) { glow }
        .clipShape(RoundedRectangle(cornerRadius: TrendsLayout.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Trends.Summary")
        .trendsReveal($isRevealed)
    }

    /// A soft wash of the consistency accent in the corner — the one
    /// ornamental touch, kept behind the content and out of accessibility.
    private var glow: some View {
        RadialGradient(
            colors: [consistencyAccent.opacity(colorScheme == .dark ? 0.24 : 0.14), .clear],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 220
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.xs) {
            Image(systemName: "waveform.path.ecg")
                .font(.caption.weight(.bold))
                .foregroundStyle(consistencyAccent)
                .accessibilityHidden(true)
            Text(range.spanTitle.uppercased())
                .font(TrendsFont.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: MarbleSpacing.xs)
            if let percent = derived.periodComparison?.setsChangePercent {
                TrendsDeltaPill(
                    percent: percent,
                    accent: consistencyAccent,
                    comparisonLabel: range.comparisonTitle
                )
                .accessibilityIdentifier("Trends.Summary.Delta")
            }
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            HStack(alignment: .lastTextBaseline, spacing: MarbleSpacing.xs) {
                Text("\(setCount)")
                    .font(TrendsFont.hero)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(setCount)))
                    .animation(TrendsMotion.isEnabled(reduceMotion: reduceMotion) ? .snappy : nil, value: setCount)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(setCount == 1 ? "set" : "sets")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            Text(headlineDetail)
                .font(MarbleTypography.rowMeta.weight(.medium))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sets, \(setCount), \(headlineDetail)")
        .accessibilityIdentifier("Trends.SummaryMetric.Sets")
    }

    private var headlineDetail: String {
        var parts = ["\(derived.activeDayCount) active \(derived.activeDayCount == 1 ? "day" : "days")"]
        if prCount > 0 {
            parts.append("\(prCount) \(prCount == 1 ? "PR" : "PRs")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Rhythm

    private var rhythm: some View {
        let summaries = derived.consistencySummaries
        let peak = derived.consistencyPRSummary?.date
        let gold = TrendsPalette.personalRecord.color(for: colorScheme)
        let unit: Calendar.Component = derived.consistencyGranularity == .week ? .weekOfYear : .day
        let maxCount = Double(max(derived.consistencyPRCount, 1))
        return Chart {
            ForEach(summaries) { item in
                BarMark(
                    x: .value("Day", item.date, unit: unit),
                    yStart: .value("Base", 0),
                    yEnd: .value("Sets", isRevealed ? max(Double(item.count), maxCount * 0.04) : maxCount * 0.04),
                    width: .ratio(0.62)
                )
                .clipShape(Capsule())
                .foregroundStyle(
                    item.count == 0
                        ? AnyShapeStyle(Theme.chipFillColor(for: colorScheme))
                        : item.date == peak
                            ? AnyShapeStyle(TrendsPalette.medallionGradient(gold))
                            : AnyShapeStyle(TrendsPalette.barGradient(consistencyAccent))
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...maxCount)
        .chartLegend(.hidden)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 64 : 52)
        .animation(TrendsMotion.isEnabled(reduceMotion: reduceMotion) ? TrendsMotion.reveal : nil, value: isRevealed)
        .accessibilityHidden(true)
    }

    // MARK: Tiles

    private var tiles: some View {
        let items = tileItems
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0..<min($0 + perRow, items.count)])
        }
        return VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: MarbleSpacing.s) {
                    ForEach(rows[rowIndex]) { item in
                        TrendsPulseTile(item: item)
                    }
                    if rows[rowIndex].count < perRow {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var tileItems: [TrendsPulseTileItem] {
        var items: [TrendsPulseTileItem] = []
        let bestWeek = derived.weeklySummaries.max { $0.setCount < $1.setCount }
        items.append(TrendsPulseTileItem(
            identifier: "BestWeek",
            title: "Best Week",
            symbol: "star.fill",
            accent: TrendsPalette.personalRecord.color(for: colorScheme),
            value: bestWeek.map { "\($0.setCount)" } ?? "0",
            unit: bestWeek.map { $0.setCount == 1 ? "set" : "sets" },
            detail: bestWeek.map { week in
                // "Jan 12 – 18": short enough to sit on one line in a half-width
                // tile without shrinking (shrunk text fails the contrast audit).
                (week.weekStart..<max(week.weekEnd, week.weekStart))
                    .formatted(.interval.month(.abbreviated).day())
            } ?? "No week yet",
            deltaPercent: nil,
            deltaLabel: nil
        ))

        let volumeKilograms = derived.weeklySummaries.reduce(0) { $0 + $1.weightedVolume }
        if volumeKilograms > 0 {
            let display = LifterAnalytics.displayWeight(fromKilograms: volumeKilograms, in: displayWeightUnit)
            items.append(TrendsPulseTileItem(
                identifier: "Volume",
                title: "Volume",
                symbol: "scalemass.fill",
                accent: TrendsPalette.volumeWeighted.color(for: colorScheme),
                value: Formatters.compactNumberText(display),
                unit: displayWeightUnit.symbol,
                detail: "Weight × reps",
                deltaPercent: derived.periodComparison?.volumeChangePercent,
                deltaLabel: range.comparisonTitle
            ))
        }

        if let effort = derived.averageEffort {
            items.append(TrendsPulseTileItem(
                identifier: "Effort",
                title: "Avg Effort",
                symbol: "bolt.fill",
                accent: TrendsPalette.effort.color(for: colorScheme),
                value: String(format: "%.1f", effort),
                unit: "RPE",
                detail: Self.effortDescriptor(effort),
                deltaPercent: nil,
                deltaLabel: nil
            ))
        }

        let supplementLogs = derived.filteredSupplementEntries.count
        if supplementLogs > 0 {
            items.append(TrendsPulseTileItem(
                identifier: "Supplements",
                title: "Supplements",
                symbol: "pills.fill",
                accent: TrendsPalette.supplements.color(for: colorScheme),
                value: "\(supplementLogs)",
                unit: supplementLogs == 1 ? "log" : "logs",
                detail: supplementFilterName ?? "All types",
                deltaPercent: nil,
                deltaLabel: nil
            ))
        }
        return items
    }

    static func effortDescriptor(_ rpe: Double) -> String {
        switch rpe {
        case ..<6: "Easy going"
        case ..<7.5: "Moderate"
        case ..<8.5: "Hard"
        default: "All out"
        }
    }
}

struct TrendsPulseTileItem: Identifiable {
    let identifier: String
    let title: String
    let symbol: String
    let accent: Color
    let value: String
    let unit: String?
    let detail: String
    let deltaPercent: Double?
    let deltaLabel: String?

    var id: String { identifier }

    var accessibilityLabel: String {
        var parts = [title, [value, unit].compactMap { $0 }.joined(separator: " "), detail]
        if let deltaPercent, abs(deltaPercent) >= 0.5 {
            parts.append(TrendsDeltaPill.accessibilityText(for: deltaPercent, comparisonLabel: deltaLabel ?? "previous period"))
        }
        return parts.joined(separator: ", ")
    }
}

private struct TrendsPulseTile: View {
    let item: TrendsPulseTileItem

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            HStack(spacing: MarbleSpacing.xs) {
                TrendsGlyphBadge(systemName: item.symbol, accent: item.accent, size: 22)
                Text(item.title)
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(item.value)
                    .font(TrendsFont.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = item.unit {
                    Text(unit)
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }
            }
            if let delta = item.deltaPercent {
                TrendsDeltaPill(percent: delta, accent: item.accent, comparisonLabel: item.deltaLabel ?? "previous period")
            } else {
                Text(item.detail)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Opaque in light mode: text over a translucent tile on the card's
            // glow resolves to an ambiguous background for the contrast audit.
            RoundedRectangle(cornerRadius: TrendsLayout.innerRadius + 2, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("Trends.SummaryMetric.\(item.identifier)")
    }
}
