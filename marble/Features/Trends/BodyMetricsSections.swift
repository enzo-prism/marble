import SwiftUI
import SwiftData
import Charts

// The body-metrics Trends surfaces added in 2.4 "Body": a bodyweight trend
// chart with its own empty state, and the relative-strength (DOTS) secondary
// line that rides under the existing estimated-1RM section.
//
// Both views are self-contained — they own their `@Query` and their own
// `RenderMemo`, so wiring them into `TrendsView` is a single line each and no
// existing derivation, section, or memo signature changes shape. Following the
// repo rule, no derivation runs inline in a `body`: every scan is behind a memo
// keyed by a cheap signature.

extension TrendsPalette {
    /// Bodyweight: a cool slate-green, distinct from the violet raw-progress
    /// line, the steel-blue e1RM line, and the teal supplements line — the HIG
    /// asks that different data read as visibly different charts.
    static let bodyweight = TrendsChartAccent(
        light: Color(red: 0.13, green: 0.52, blue: 0.44),
        dark: Color(red: 0.40, green: 0.82, blue: 0.70)
    )
}

// MARK: - Derived data

/// Everything the bodyweight chart needs, derived once per signature change.
struct BodyweightTrendData: Equatable {
    struct Point: Identifiable, Equatable {
        let date: Date
        /// Canonical kilograms, for comparisons.
        let kilograms: Double
        /// The same value in the lifter's display unit.
        let displayValue: Double
        let bodyFatPercent: Double?

        var id: Date { date }
    }

    let points: [Point]
    let displayUnit: WeightUnit
    /// Most recent measurement in the range.
    let latest: Point?
    /// Last minus first, in the display unit. Nil when there is only one
    /// measurement — a single weigh-in has no trend to report.
    let changeInDisplayUnit: Double?
    let averageDisplayValue: Double
    let accessibilityValue: String

    var isEmpty: Bool { points.isEmpty }

    /// One point per calendar day (last measurement of the day wins), oldest
    /// first. Pure so it is unit-testable without a view.
    static func build(
        entries: [BodyMetricEntry],
        displayUnit: WeightUnit,
        calendar: Calendar = .current
    ) -> BodyweightTrendData {
        var byDay: [Date: BodyMetricEntry] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.measuredAt)
            if let existing = byDay[day], existing.measuredAt >= entry.measuredAt { continue }
            byDay[day] = entry
        }

        let points: [Point] = byDay.keys.sorted().compactMap { day in
            guard let entry = byDay[day] else { return nil }
            return Point(
                date: day,
                kilograms: entry.weightKilograms,
                displayValue: entry.displayWeight(in: displayUnit),
                bodyFatPercent: entry.bodyFatPercent
            )
        }

        let values = points.map(\.displayValue)
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let change: Double? = points.count > 1
            ? (points.last?.displayValue ?? 0) - (points.first?.displayValue ?? 0)
            : nil

        return BodyweightTrendData(
            points: points,
            displayUnit: displayUnit,
            latest: points.last,
            changeInDisplayUnit: change,
            averageDisplayValue: average,
            accessibilityValue: makeAccessibilityValue(
                points: points,
                unit: displayUnit,
                change: change
            )
        )
    }

    private static func makeAccessibilityValue(
        points: [Point],
        unit: WeightUnit,
        change: Double?
    ) -> String {
        guard let latest = points.last else { return "No data" }
        let latestText = Formatters.weight.string(from: NSNumber(value: latest.displayValue))
            ?? "\(Int(latest.displayValue))"
        var text = "Latest \(latestText) \(unit.symbol) across \(points.count) measurements"
        if let change {
            let magnitude = Formatters.weight.string(from: NSNumber(value: abs(change)))
                ?? "\(Int(abs(change)))"
            if abs(change) < 0.05 {
                text += ", unchanged over this range"
            } else {
                text += ", \(change > 0 ? "up" : "down") \(magnitude) \(unit.symbol) over this range"
            }
        }
        return text
    }
}

/// Cheap, `Equatable` fingerprint of the rows behind the chart.
struct BodyweightTrendSignature: Equatable {
    let count: Int
    let firstMeasuredAt: Date?
    let lastMeasuredAt: Date?
    let lastUpdatedAt: Date?
    let displayUnit: WeightUnit
}

// MARK: - Bodyweight trend section

/// Drop-in Trends section: the bodyweight chart, or an empty state inviting the
/// first entry. Owns its own range-scoped query so `TrendsView` needs one line.
struct BodyweightTrendSection: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    /// Range-scoped at init, exactly like `TrendsContentView`'s own queries, so
    /// only rows the chart can show are fetched and kept live.
    @Query private var metrics: [BodyMetricEntry]

    @State private var memo = RenderMemo<BodyweightTrendSignature, BodyweightTrendData>()

    private let onLogWeight: () -> Void

    init(range: TrendRange, onLogWeight: @escaping () -> Void) {
        self.onLogWeight = onLogWeight
        if let startDate = range.startDate {
            _metrics = Query(
                filter: #Predicate<BodyMetricEntry> { $0.measuredAt >= startDate },
                sort: \BodyMetricEntry.measuredAt,
                order: .forward
            )
        } else {
            _metrics = Query(sort: \BodyMetricEntry.measuredAt, order: .forward)
        }
    }

    private var displayUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    private var signature: BodyweightTrendSignature {
        BodyweightTrendSignature(
            count: metrics.count,
            firstMeasuredAt: metrics.first?.measuredAt,
            lastMeasuredAt: metrics.last?.measuredAt,
            lastUpdatedAt: metrics.map(\.updatedAt).max(),
            displayUnit: displayUnit
        )
    }

    var body: some View {
        let data = memo.value(for: signature) {
            BodyweightTrendData.build(entries: metrics, displayUnit: displayUnit)
        }

        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            header(data: data)

            if data.isEmpty {
                emptyState
            } else {
                chart(data: data)

                Text("One point per day, using your last weigh-in that day. Logged in kilograms underneath, so switching units never rewrites your history.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(data: BodyweightTrendData) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Bodyweight")
                .font(MarbleTypography.sectionTitle)
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Trends.Section.Bodyweight")

            Spacer(minLength: MarbleSpacing.s)

            Button(action: onLogWeight) {
                Label("Log", systemImage: "plus")
                    .font(MarbleTypography.rowMeta)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TrendsPalette.bodyweight.color(for: colorScheme))
            .accessibilityLabel("Log weight")
            .accessibilityIdentifier("Trends.Bodyweight.Log")
        }

        if let latest = data.latest {
            Text(summaryText(data: data, latest: latest))
                .font(MarbleTypography.rowMeta)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("Trends.Bodyweight.Latest")
        }
    }

    private func summaryText(data: BodyweightTrendData, latest: BodyweightTrendData.Point) -> String {
        var parts = ["\(weightText(latest.displayValue)) \(data.displayUnit.symbol)"]
        if let change = data.changeInDisplayUnit {
            if abs(change) < 0.05 {
                parts.append("no change")
            } else {
                // Plain sign characters, never emoji — this is caption type.
                parts.append("\(change > 0 ? "+" : "\u{2212}")\(weightText(abs(change))) \(data.displayUnit.symbol)")
            }
        }
        if let bodyFat = latest.bodyFatPercent {
            parts.append("\(weightText(bodyFat))% body fat")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: MarbleSpacing.s) {
            // The identifier goes on the leaf, never on the enclosing VStack:
            // a container identifier overrides its children and would swallow
            // the button's own identifier below.
            EmptyStateView(
                title: "No weigh-ins yet",
                message: "Log your bodyweight to see it trend here — and to unlock relative strength on your lifts.",
                systemImage: "figure.stand"
            )
            .accessibilityIdentifier("Trends.Bodyweight.EmptyState")

            Button(action: onLogWeight) {
                Text("Log Weight")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
            .accessibilityIdentifier("Trends.Bodyweight.EmptyLog")
        }
    }

    // MARK: Chart

    private func chart(data: BodyweightTrendData) -> some View {
        let accent = TrendsPalette.bodyweight.color(for: colorScheme)
        let values = data.points.map(\.displayValue)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        // Bodyweight moves in small percentages, so a zero-based axis would
        // flatten every real trend into a straight line. Pad tightly around the
        // observed span instead, the same way the e1RM chart does.
        let padding = max((maxValue - minValue) * 0.20, maxValue * 0.01, 0.5)
        let domain = max(0, minValue - padding) ... (maxValue + padding)

        return Chart {
            ForEach(data.points) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    y: .value("Bodyweight", point.displayValue)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(TrendsPalette.areaGradient(accent))
                .accessibilityHidden(true)
            }

            ForEach(data.points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Bodyweight", point.displayValue)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(Text(point.date, format: .dateTime.month(.abbreviated).day()))
                .accessibilityValue("\(weightText(point.displayValue)) \(data.displayUnit.symbol)")
            }

            if data.points.count > 1 {
                RuleMark(y: .value("Average", data.averageDisplayValue))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 180)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(Theme.surfaceColor(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
                .padding(.trailing, MarbleSpacing.xs)
        }
        .accessibilityLabel("Bodyweight chart")
        .accessibilityValue(data.accessibilityValue)
        .accessibilityIdentifier("Trends.BodyweightChart")
    }

    private func weightText(_ value: Double) -> String {
        Formatters.weight.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Relative strength (DOTS) secondary line

/// Cheap signature for the relative-strength memo.
struct RelativeStrengthSignature: Equatable {
    let liftDates: [Date]
    let bodyweightCount: Int
    let lastBodyweightAt: Date?
    let usesFemaleCoefficients: Bool
}

/// Secondary line for the existing estimated-1RM section: this lift's e1RM
/// expressed on the DOTS bodyweight-relative scale.
///
/// Renders **nothing** when there is no bodyweight within
/// `LifterAnalytics.bodyweightLookupWindowDays` of any training day — the metric
/// is omitted rather than guessed. That means it is safe to place
/// unconditionally under `OneRepMaxSectionView`.
struct RelativeStrengthLine: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(BodyMetricsPreferences.dotsUsesFemaleCoefficientsKey)
    private var dotsUsesFemaleCoefficients = false

    /// Scoped at init to the e1RM series' span widened by the lookup window —
    /// the only rows that can possibly match.
    @Query private var metrics: [BodyMetricEntry]

    @State private var memo = RenderMemo<RelativeStrengthSignature, LifterAnalytics.RelativeStrengthSummary?>()

    private let series: LifterAnalytics.OneRepMaxSeries

    init(series: LifterAnalytics.OneRepMaxSeries) {
        self.series = series

        let window = Double(LifterAnalytics.bodyweightLookupWindowDays) * 86_400
        if let earliest = series.points.first?.date {
            let lowerBound = earliest.addingTimeInterval(-window)
            _metrics = Query(
                filter: #Predicate<BodyMetricEntry> { $0.measuredAt >= lowerBound },
                sort: \BodyMetricEntry.measuredAt,
                order: .forward
            )
        } else {
            _metrics = Query(sort: \BodyMetricEntry.measuredAt, order: .forward)
        }
    }

    private var signature: RelativeStrengthSignature {
        RelativeStrengthSignature(
            liftDates: series.points.map(\.date),
            bodyweightCount: metrics.count,
            lastBodyweightAt: metrics.last?.measuredAt,
            usesFemaleCoefficients: dotsUsesFemaleCoefficients
        )
    }

    var body: some View {
        let summary = memo.value(for: signature) {
            LifterAnalytics.relativeStrength(
                oneRepMax: series,
                bodyweights: metrics.map { LifterAnalytics.BodyweightSample($0) },
                isFemale: dotsUsesFemaleCoefficients
            )
        }

        if let summary, let latest = summary.latest {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Text(latestText(latest, best: summary.best))
                    .font(MarbleTypography.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Trends.RelativeStrength.Value")

                Text(explanation(latest))
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func latestText(
        _ latest: LifterAnalytics.RelativeStrengthPoint,
        best: LifterAnalytics.RelativeStrengthPoint?
    ) -> String {
        var text = "Relative strength \(score(latest.dots)) DOTS"
        if let best, best.dots > latest.dots {
            text += " \u{00B7} best \(score(best.dots))"
        }
        return text
    }

    /// Honest about what is being scored: DOTS was designed for a powerlifting
    /// total, and this is one lift's estimate. Also honest about how fresh the
    /// bodyweight behind it is.
    private func explanation(_ latest: LifterAnalytics.RelativeStrengthPoint) -> String {
        let freshness: String
        switch latest.bodyweightAgeDays {
        case 0:
            freshness = "your weigh-in that day"
        case 1:
            freshness = "a weigh-in 1 day away"
        default:
            freshness = "a weigh-in \(latest.bodyweightAgeDays) days away"
        }
        return "DOTS scales this lift's estimated 1RM against \(freshness). It is the powerlifting DOTS scale applied to one lift, not a three-lift competition total."
    }

    private func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
