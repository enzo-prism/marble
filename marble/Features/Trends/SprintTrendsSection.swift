import SwiftUI
import SwiftData
import Charts

/// Pure derivation for the sprint Trends charts. Input rows are pre-joined by
/// the section (entry × goal snapshot × optional tenths detail) so every rule
/// here is unit-testable without a store.
nonisolated enum SprintTrendsBuilder {
    struct Rep: Equatable {
        let performedAt: Date
        let distanceMeters: Double
        /// Precise tenths where a detail exists, legacy whole seconds ×10
        /// otherwise — one comparison domain (`SprintTiming`).
        let tenths: Int
        /// Nil when the rep wasn't scored (distance mismatch, missing time).
        let isHit: Bool?
    }

    struct WeekBar: Equatable {
        let weekStart: Date
        let scored: Int
        let hits: Int

        var hitRatePercent: Double {
            guard scored > 0 else { return 0 }
            return (Double(hits) / Double(scored) * 100).rounded()
        }
    }

    struct BestTimePoint: Equatable, Identifiable {
        let day: Date
        let tenths: Int

        var id: Date { day }
        var seconds: Double { SprintTiming.seconds(fromTenths: tenths) }
    }

    struct Derived: Equatable {
        let weekBars: [WeekBar]
        /// The most-logged sprint distance in range — the one progression the
        /// athlete is actually training.
        let focusDistanceMeters: Double?
        let bestTimePoints: [BestTimePoint]
        /// All-time-in-range fastest at the focus distance.
        let recordPoint: BestTimePoint?

        var isEmpty: Bool { weekBars.isEmpty && bestTimePoints.isEmpty }

        static let empty = Derived(weekBars: [], focusDistanceMeters: nil, bestTimePoints: [], recordPoint: nil)
    }

    /// How many trailing weeks the hit-rate chart shows.
    static let hitRateWeekCount = 8

    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func derive(reps: [Rep], now: Date, calendar: Calendar = .current) -> Derived {
        guard !reps.isEmpty else { return .empty }

        // Weekly hit rate over the trailing window, only weeks with scored
        // reps. Week-start rule byte-identical to `TrendsDateHelper.startOfWeek`
        // (which is main-actor and unreachable from this pure builder).
        let currentWeekStart = startOfWeek(for: now, calendar: calendar)
        let scored = reps.filter { $0.isHit != nil }
        let byWeek = Dictionary(grouping: scored) {
            startOfWeek(for: $0.performedAt, calendar: calendar)
        }
        let weekBars: [WeekBar] = (0..<hitRateWeekCount).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let weekReps = byWeek[weekStart], !weekReps.isEmpty else { return nil }
            return WeekBar(
                weekStart: weekStart,
                scored: weekReps.count,
                hits: weekReps.filter { $0.isHit == true }.count
            )
        }

        // Focus distance: most reps logged, ties to the shorter distance
        // (speed work over tempo — arbitrary but stable).
        let byDistance = Dictionary(grouping: reps) { (($0.distanceMeters * 10).rounded()) / 10 }
        let focus = byDistance.max { lhs, rhs in
            if lhs.value.count == rhs.value.count { return lhs.key > rhs.key }
            return lhs.value.count < rhs.value.count
        }?.key

        var bestTimePoints: [BestTimePoint] = []
        if let focus {
            let focusReps = byDistance[focus] ?? []
            let byDay = Dictionary(grouping: focusReps) { calendar.startOfDay(for: $0.performedAt) }
            bestTimePoints = byDay.keys.sorted().compactMap { day in
                guard let best = byDay[day]?.map(\.tenths).min() else { return nil }
                return BestTimePoint(day: day, tenths: best)
            }
        }
        let record = bestTimePoints.min { $0.tenths < $1.tenths }

        return Derived(
            weekBars: weekBars,
            focusDistanceMeters: focus,
            bestTimePoints: bestTimePoints,
            recordPoint: record
        )
    }
}

/// The sprint block in Trends: best-time progression at the athlete's main
/// distance, and weekly goal hit rate. Self-hiding when the range holds no
/// sprint reps.
///
/// Data shape follows the bodyweight lesson (see the `latestUpdatedBodyMetrics`
/// comment in `TrendsContentView`): the snapshots and tenths details are
/// fetched ONE-SHOT per memo rebuild, never held as additional unbounded live
/// queries in an already query-heavy view.
struct SprintTrendsSection: View {
    let entries: [SetEntry]
    /// Freshness token from the parent's one-row probe — a changed entry
    /// (including a tenths edit, which stamps `updatedAt`) rebuilds the memo.
    let latestEntryUpdate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.marbleActiveDay) private var activeDay

    @State private var derivedMemo = RenderMemo<SprintTrendsSignature, SprintTrendsBuilder.Derived>()

    var body: some View {
        let derived = derived
        if !derived.isEmpty {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                Text("Sprints")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("Trends.Section.Sprints")

                if let focus = derived.focusDistanceMeters, derived.bestTimePoints.count >= 2 {
                    bestTimeChart(derived: derived, focusMeters: focus)
                }

                if !derived.weekBars.isEmpty {
                    hitRateChart(bars: derived.weekBars)
                }
            }
        }
    }

    private var derived: SprintTrendsBuilder.Derived {
        let signature = SprintTrendsSignature(
            entryCount: entries.count,
            latestUpdate: latestEntryUpdate,
            day: activeDay
        )
        return derivedMemo.value(for: signature) {
            let entryIDs = entries.map(\.id)
            let snapshots = (try? modelContext.fetch(FetchDescriptor<SprintGoalSnapshot>(
                predicate: #Predicate { entryIDs.contains($0.setEntryID) }
            ))) ?? []
            guard !snapshots.isEmpty else { return .empty }
            let details = (try? modelContext.fetch(FetchDescriptor<SprintRepDetail>(
                predicate: #Predicate { entryIDs.contains($0.setEntryID) }
            ))) ?? []
            let detailByEntry = Dictionary(uniqueKeysWithValues: details.map { ($0.setEntryID, $0) })
            let snapshotByEntry = Dictionary(
                snapshots.map { ($0.setEntryID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let reps: [SprintTrendsBuilder.Rep] = entries.compactMap { entry in
                guard let snapshot = snapshotByEntry[entry.id],
                      let distance = entry.distance, distance > 0 else { return nil }
                let detail = detailByEntry[entry.id]
                let tenths: Int
                if let detail {
                    tenths = detail.durationTenths
                } else if let seconds = entry.durationSeconds, seconds > 0 {
                    tenths = SprintTiming.tenths(fromWholeSeconds: seconds)
                } else {
                    return nil
                }
                let evaluation = SprintGoalEvaluation.evaluate(snapshot: snapshot, entry: entry, detail: detail)
                let isHit: Bool? = evaluation.status == .notScored ? nil : evaluation.didHit
                return SprintTrendsBuilder.Rep(
                    performedAt: entry.performedAt,
                    distanceMeters: entry.distanceUnit.meters(from: distance),
                    tenths: tenths,
                    isHit: isHit
                )
            }
            return SprintTrendsBuilder.derive(reps: reps, now: AppEnvironment.now)
        }
    }

    // MARK: - Best time

    @ViewBuilder
    private func bestTimeChart(derived: SprintTrendsBuilder.Derived, focusMeters: Double) -> some View {
        let accent = TrendsPalette.sprint.color(for: colorScheme)
        let distanceText = distanceLabel(meters: focusMeters)
        let summary = bestTimeSummary(derived: derived, distanceText: distanceText)

        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Best \(distanceText) Time")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)

            Chart {
                ForEach(derived.bestTimePoints) { point in
                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("Best time", point.seconds)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(TrendsPalette.areaGradient(accent))
                    .accessibilityHidden(true)
                }

                ForEach(derived.bestTimePoints) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Best time", point.seconds)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(Text(point.day, format: .dateTime.month(.abbreviated).day()))
                    .accessibilityValue(SprintTiming.text(tenths: point.tenths))
                }

                if let record = derived.recordPoint {
                    PointMark(
                        x: .value("Record Day", record.day),
                        y: .value("Best time", record.seconds)
                    )
                    .symbol {
                        TrendsPRDot()
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: 180)
            .chartYScale(domain: bestTimeDomain(derived: derived))
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
            .accessibilityLabel("Best sprint time chart")
            .accessibilityValue(summary)
            .accessibilityIdentifier("Trends.SprintBestTimeChart")
            .accessibilityChartDescriptor(TrendsDateSeriesAudioGraph(
                title: "Best \(distanceText) time",
                summary: summary,
                valueAxisName: "Best time",
                valueUnit: "seconds",
                seriesName: "Best time",
                points: derived.bestTimePoints.map { point in
                    TrendsDateSeriesAudioGraph.Point(
                        date: point.day,
                        value: point.seconds,
                        valueText: SprintTiming.text(tenths: point.tenths)
                    )
                }
            ))
        }
    }

    /// A tight domain padded by half a second each side; sprint deltas are
    /// tenths, and a zero-anchored axis would flatten the line into noise.
    private func bestTimeDomain(derived: SprintTrendsBuilder.Derived) -> ClosedRange<Double> {
        let values = derived.bestTimePoints.map(\.seconds)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...1 }
        return max(0, minValue - 0.5)...(maxValue + 0.5)
    }

    private func bestTimeSummary(derived: SprintTrendsBuilder.Derived, distanceText: String) -> String {
        guard let record = derived.recordPoint else { return "No timed sprints in this range." }
        return "Fastest \(distanceText): \(SprintTiming.text(tenths: record.tenths)) on \(TrendsAudioGraph.spokenDay(for: record.day)), across \(derived.bestTimePoints.count) training days."
    }

    private func distanceLabel(meters: Double) -> String {
        let formatted = Formatters.distance.string(from: NSNumber(value: meters)) ?? "\(meters)"
        return "\(formatted) m"
    }

    // MARK: - Hit rate

    @ViewBuilder
    private func hitRateChart(bars: [SprintTrendsBuilder.WeekBar]) -> some View {
        let accent = TrendsPalette.sprint.color(for: colorScheme)
        let summary = hitRateSummary(bars: bars)

        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Goal Hit Rate")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)

            Chart(bars, id: \.weekStart) { bar in
                BarMark(
                    x: .value("Week", bar.weekStart, unit: .weekOfYear),
                    y: .value("Hit rate", bar.hitRatePercent)
                )
                .foregroundStyle(TrendsPalette.barGradient(accent))
                .cornerRadius(3)
                .accessibilityLabel(Text(bar.weekStart, format: .dateTime.month(.abbreviated).day()))
                .accessibilityValue("\(Int(bar.hitRatePercent)) percent, \(bar.hits) of \(bar.scored) reps")
            }
            .frame(height: 180)
            .chartYScale(domain: 0...100)
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
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
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
            .accessibilityLabel("Sprint goal hit rate chart")
            .accessibilityValue(summary)
            .accessibilityIdentifier("Trends.SprintHitRateChart")
            .accessibilityChartDescriptor(TrendsCategoryAudioGraph(
                title: "Sprint goal hit rate",
                summary: summary,
                categoryAxisName: "Week",
                valueAxisName: "Hit rate",
                valueUnit: "percent",
                bars: bars.map { bar in
                    TrendsCategoryAudioGraph.Bar(
                        category: TrendsAudioGraph.spokenDay(for: bar.weekStart),
                        value: bar.hitRatePercent,
                        valueText: "\(Int(bar.hitRatePercent)) percent, \(bar.hits) of \(bar.scored) reps"
                    )
                }
            ))
        }
    }

    private func hitRateSummary(bars: [SprintTrendsBuilder.WeekBar]) -> String {
        guard let latest = bars.last else { return "No scored sprint reps in this range." }
        return "This week \(latest.hits) of \(latest.scored) scored reps hit the goal, across \(bars.count) recent weeks."
    }
}

private nonisolated struct SprintTrendsSignature: Equatable {
    let entryCount: Int
    let latestUpdate: Date
    let day: Date
}
