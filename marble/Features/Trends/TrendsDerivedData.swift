import Foundation

/// Everything the Trends screen derives from the raw queries, built exactly once
/// per body evaluation. The previous chained computed properties re-filtered and
/// re-grouped the full entry list many times per render (and per scrub frame).
struct TrendsDerivedData {
    enum ConsistencyGranularity {
        case day
        case week

        var bucketLengthDays: Int {
            switch self {
            case .day:
                return 1
            case .week:
                return 7
            }
        }
    }

    let filteredEntries: [SetEntry]
    let filteredSupplementEntries: [SupplementEntry]
    let activeDayCount: Int

    let consistencyGranularity: ConsistencyGranularity
    let consistencySummaries: [TrendDailySummary]
    let consistencyPRCount: Int
    let consistencyPRSummary: TrendDailySummary?

    let weeklySummaries: [TrendWeeklySummary]
    let volumeData: [VolumeDatum]
    let weeklyPRTotal: Double
    let weeklyPRSummary: TrendWeeklySummary?

    let supplementDisplayMode: SupplementTrendDisplayMode
    let supplementSummaries: [SupplementDailySummary]
    let supplementSummariesWithLogs: [SupplementDailySummary]

    let progressPoints: [ExerciseProgressPoint]
    let liftBests: ExerciseLiftBests?

    // Lifter analytics (see LifterAnalytics): estimated-1RM progression for
    // the selected exercise, rep-range distribution, and the effort
    // (average-RPE) trend — all derived from the same filtered entries in
    // this one build pass.
    let oneRepMaxSeries: LifterAnalytics.OneRepMaxSeries?
    let repRangeBuckets: [LifterAnalytics.RepRangeBucket]
    /// Consistency buckets that actually contain sets, re-used as the effort
    /// series (their `averageRPE` is already derived per bucket).
    let effortSummaries: [TrendDailySummary]

    // Coaching layer (see LifterCoaching / TrainingConsistency /
    // MonthlyReportBuilder). These read full history — verdicts, records, and
    // streaks describe the lifter, not the visible range — so `build` takes
    // the one-shot `historyEntries` fetch alongside the range-scoped rows.
    let strengthAssessments: [LifterCoaching.ProgressionAssessment]
    let doubleProgressionHint: LifterCoaching.DoubleProgressionHint?
    let repRecords: [LifterCoaching.RepRecord]
    let prEvents: [LifterCoaching.PREvent]
    let muscleCoverage: [LifterCoaching.MuscleGroupCoverage]
    let consistencySnapshot: TrainingConsistency.Snapshot
    let monthlyReport: MonthlyReport?

    // PR-card bests, derived once here instead of re-scanning `filteredEntries`
    // inside the view body on every render (including chart scrubbing).
    let bestWeightEntry: SetEntry?
    let bestDistanceEntry: SetEntry?
    let fastestSpeedEntry: SetEntry?
    let bestReps: Int?
    let bestDuration: Int?

    // Accessibility summaries, also derived once: the chart `.accessibilityValue`
    // closures previously re-reduced these arrays on every render.
    let consistencyAccessibilityValue: String
    let volumeAccessibilityValue: String
    let supplementAccessibilityValue: String
    let oneRepMaxAccessibilityValue: String
    let muscleGroupAccessibilityValue: String
    let effortAccessibilityValue: String

    static func build(
        entries: [SetEntry],
        supplementEntries: [SupplementEntry],
        historyEntries: [SetEntry],
        selectedExercise: Exercise?,
        selectedSupplementType: SupplementType?,
        range: TrendRange,
        weeklyTarget: Int = TrainingConsistency.defaultWeeklyTarget,
        calendar: Calendar = .current,
        now: Date = AppEnvironment.now
    ) -> TrendsDerivedData {
        let startDate = range.startDate
        let selectedExerciseID = selectedExercise?.id

        var filteredEntries: [SetEntry] = []
        filteredEntries.reserveCapacity(entries.count)
        for entry in entries {
            if let selectedExerciseID, entry.exercise.id != selectedExerciseID { continue }
            if let startDate, entry.performedAt < startDate { continue }
            filteredEntries.append(entry)
        }

        let selectedSupplementTypeID = selectedSupplementType?.id
        var filteredSupplementEntries: [SupplementEntry] = []
        for entry in supplementEntries {
            if let selectedSupplementTypeID, entry.type.id != selectedSupplementTypeID { continue }
            if let startDate, entry.takenAt < startDate { continue }
            filteredSupplementEntries.append(entry)
        }

        let granularity: ConsistencyGranularity = (range == .oneYear || range == .all) ? .week : .day

        let dayGroups = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.performedAt) }
        let weekGroups = Dictionary(grouping: filteredEntries) { TrendsDateHelper.startOfWeek(for: $0.performedAt, calendar: calendar) }

        let consistencySummaries: [TrendDailySummary]
        switch granularity {
        case .day:
            consistencySummaries = bucketSummaries(
                groups: dayGroups,
                range: range,
                bucketStart: startDate,
                advance: { calendar.date(byAdding: .day, value: 1, to: $0) },
                now: calendar.startOfDay(for: now)
            ).map { TrendDailySummary(date: $0.0, entries: $0.1) }
        case .week:
            consistencySummaries = bucketSummaries(
                groups: weekGroups,
                range: range,
                bucketStart: startDate.map { TrendsDateHelper.startOfWeek(for: $0, calendar: calendar) },
                advance: { calendar.date(byAdding: .day, value: 7, to: $0) },
                now: TrendsDateHelper.startOfWeek(for: now, calendar: calendar)
            ).map { TrendDailySummary(date: $0.0, entries: $0.1) }
        }

        let consistencyPRCount = consistencySummaries.map(\.count).max() ?? 0
        let consistencyPRSummary = consistencyPRCount > 0
            ? consistencySummaries.filter { $0.count == consistencyPRCount }.max(by: { $0.date < $1.date })
            : nil

        var weeklySummaries: [TrendWeeklySummary] = []
        weeklySummaries.reserveCapacity(weekGroups.count)
        for (weekStart, items) in weekGroups {
            var weightedVolume: Double = 0
            var repsVolume: Int = 0
            var durationSeconds: Int = 0

            for item in items {
                if let weight = item.weight, let reps = item.reps {
                    weightedVolume += weight * Double(reps)
                } else if let reps = item.reps {
                    repsVolume += reps
                }
                if let duration = item.durationSeconds {
                    durationSeconds += duration
                }
            }

            let durationMinutes = Double(durationSeconds) / 60.0
            weeklySummaries.append(TrendWeeklySummary(
                weekStart: weekStart,
                weekEnd: TrendsDateHelper.endOfWeek(for: weekStart, calendar: calendar),
                entries: items,
                weightedVolume: weightedVolume,
                repsVolume: repsVolume,
                durationMinutes: durationMinutes,
                maxSeriesValue: max(weightedVolume, Double(repsVolume), durationMinutes)
            ))
        }
        weeklySummaries.sort { $0.weekStart < $1.weekStart }

        var volumeData: [VolumeDatum] = []
        for summary in weeklySummaries {
            if summary.weightedVolume > 0 {
                volumeData.append(VolumeDatum(weekStart: summary.weekStart, series: .weighted, value: summary.weightedVolume))
            }
            if summary.repsVolume > 0 {
                volumeData.append(VolumeDatum(weekStart: summary.weekStart, series: .reps, value: Double(summary.repsVolume)))
            }
            if summary.durationMinutes > 0 {
                volumeData.append(VolumeDatum(weekStart: summary.weekStart, series: .duration, value: summary.durationMinutes))
            }
        }

        let weeklyPRTotal = weeklySummaries.map(\.totalVolumeScore).max() ?? 0
        let weeklyPRSummary = weeklyPRTotal > 0
            ? weeklySummaries.filter { $0.totalVolumeScore == weeklyPRTotal }.max(by: { $0.weekStart < $1.weekStart })
            : nil

        let supplementDisplayMode = resolveSupplementDisplayMode(
            entries: filteredSupplementEntries,
            selectedType: selectedSupplementType
        )

        let supplementGroups: [Date: [SupplementEntry]]
        switch granularity {
        case .day:
            supplementGroups = Dictionary(grouping: filteredSupplementEntries) { calendar.startOfDay(for: $0.takenAt) }
        case .week:
            supplementGroups = Dictionary(grouping: filteredSupplementEntries) { TrendsDateHelper.startOfWeek(for: $0.takenAt, calendar: calendar) }
        }

        let supplementBuckets: [(Date, [SupplementEntry])]
        switch granularity {
        case .day:
            supplementBuckets = bucketSummaries(
                groups: supplementGroups,
                range: range,
                bucketStart: startDate,
                advance: { calendar.date(byAdding: .day, value: 1, to: $0) },
                now: calendar.startOfDay(for: now)
            )
        case .week:
            supplementBuckets = bucketSummaries(
                groups: supplementGroups,
                range: range,
                bucketStart: startDate.map { TrendsDateHelper.startOfWeek(for: $0, calendar: calendar) },
                advance: { calendar.date(byAdding: .day, value: 7, to: $0) },
                now: TrendsDateHelper.startOfWeek(for: now, calendar: calendar)
            )
        }
        let resolvedSupplementSummaries = supplementBuckets.map {
            SupplementDailySummary(date: $0.0, entries: $0.1, mode: supplementDisplayMode)
        }

        // Compare in kilograms so a 100 kg set beats a 200 lb set — the same
        // normalization the PR engine and lift bests use.
        let bestWeightEntry = filteredEntries
            .filter { $0.weight != nil }
            .max {
                PersonalRecords.kilograms($0.weight ?? 0, unit: $0.weightUnit)
                    < PersonalRecords.kilograms($1.weight ?? 0, unit: $1.weightUnit)
            }
        // Compare in meters so a 6 mi run beats a 200 m sprint regardless of
        // the unit each entry was logged in.
        let bestDistanceEntry = filteredEntries
            .filter { $0.distance != nil }
            .max { $0.distanceUnit.meters(from: $0.distance ?? 0) < $1.distanceUnit.meters(from: $1.distance ?? 0) }
        let fastestSpeedEntry = filteredEntries
            .filter { ($0.distance ?? 0) > 0 && ($0.durationSeconds ?? 0) > 0 }
            .max { lhs, rhs in
                let lhsSpeed = lhs.distanceUnit.meters(from: lhs.distance ?? 0) / Double(max(lhs.durationSeconds ?? 1, 1))
                let rhsSpeed = rhs.distanceUnit.meters(from: rhs.distance ?? 0) / Double(max(rhs.durationSeconds ?? 1, 1))
                return lhsSpeed < rhsSpeed
            }
        let bestReps = filteredEntries.compactMap { $0.reps }.max()
        let bestDuration = filteredEntries.compactMap { $0.durationSeconds }.max()

        let oneRepMaxSeries = selectedExercise.flatMap {
            LifterAnalytics.oneRepMaxSeries(entries: filteredEntries, exercise: $0, calendar: calendar)
        }
        let repRangeBuckets = LifterAnalytics.repRangeDistribution(entries: filteredEntries)
        let effortSummaries = consistencySummaries.filter { $0.count > 0 }

        // Coaching layer. Range entries say what the lifter is doing now;
        // history says where their records and streaks actually stand.
        let strengthAssessments = LifterCoaching.topLiftAssessments(
            rangeEntries: filteredEntries,
            history: historyEntries,
            calendar: calendar
        )
        let doubleProgressionHint = selectedExercise.flatMap {
            LifterCoaching.doubleProgressionHint(history: historyEntries, exercise: $0, calendar: calendar)
        }
        let repRecords = selectedExercise.map {
            LifterCoaching.repRecords(history: historyEntries, exercise: $0)
        } ?? []
        let prEvents = LifterCoaching.prEvents(
            history: historyEntries,
            rangeStart: startDate,
            selectedExerciseID: selectedExerciseID,
            calendar: calendar
        )
        let muscleCoverage = LifterCoaching.muscleGroupCoverage(
            rangeEntries: filteredEntries,
            history: historyEntries,
            weekCount: LifterAnalytics.weekCount(range: range, entries: filteredEntries, now: now),
            now: now,
            calendar: calendar
        )
        let consistencySnapshot = TrainingConsistency.snapshot(
            history: historyEntries,
            target: weeklyTarget,
            now: now,
            calendar: calendar
        )
        let monthlyReport = MonthlyReportBuilder.build(history: historyEntries, now: now, calendar: calendar)

        let usesWeeks = granularity == .week

        return TrendsDerivedData(
            filteredEntries: filteredEntries,
            filteredSupplementEntries: filteredSupplementEntries,
            activeDayCount: dayGroups.count,
            consistencyGranularity: granularity,
            consistencySummaries: consistencySummaries,
            consistencyPRCount: consistencyPRCount,
            consistencyPRSummary: consistencyPRSummary,
            weeklySummaries: weeklySummaries,
            volumeData: volumeData,
            weeklyPRTotal: weeklyPRTotal,
            weeklyPRSummary: weeklyPRSummary,
            supplementDisplayMode: supplementDisplayMode,
            supplementSummaries: resolvedSupplementSummaries,
            supplementSummariesWithLogs: resolvedSupplementSummaries.filter { $0.count > 0 },
            progressPoints: selectedExercise.map { ExerciseProgressBuilder.buildPoints(entries: filteredEntries, exercise: $0, range: range) } ?? [],
            liftBests: selectedExercise.flatMap { ExerciseProgressBuilder.buildLiftBests(entries: filteredEntries, exercise: $0, range: range) },
            oneRepMaxSeries: oneRepMaxSeries,
            repRangeBuckets: repRangeBuckets,
            effortSummaries: effortSummaries,
            strengthAssessments: strengthAssessments,
            doubleProgressionHint: doubleProgressionHint,
            repRecords: repRecords,
            prEvents: prEvents,
            muscleCoverage: muscleCoverage,
            consistencySnapshot: consistencySnapshot,
            monthlyReport: monthlyReport,
            bestWeightEntry: bestWeightEntry,
            bestDistanceEntry: bestDistanceEntry,
            fastestSpeedEntry: fastestSpeedEntry,
            bestReps: bestReps,
            bestDuration: bestDuration,
            consistencyAccessibilityValue: Self.makeConsistencyAccessibilityValue(consistencySummaries, usesWeeks: usesWeeks),
            volumeAccessibilityValue: Self.makeVolumeAccessibilityValue(volumeData),
            supplementAccessibilityValue: Self.makeSupplementAccessibilityValue(resolvedSupplementSummaries, mode: supplementDisplayMode, usesWeeks: usesWeeks),
            oneRepMaxAccessibilityValue: Self.makeOneRepMaxAccessibilityValue(oneRepMaxSeries),
            muscleGroupAccessibilityValue: Self.makeMuscleGroupAccessibilityValue(muscleCoverage),
            effortAccessibilityValue: Self.makeEffortAccessibilityValue(effortSummaries, usesWeeks: usesWeeks)
        )
    }

    private static func makeOneRepMaxAccessibilityValue(_ series: LifterAnalytics.OneRepMaxSeries?) -> String {
        guard let series, let best = series.best else { return "No data" }
        let bestText = Formatters.weight.string(from: NSNumber(value: best.displayValue)) ?? "\(Int(best.displayValue))"
        return "Best estimated one rep max \(bestText) \(series.displayUnit.symbol), across \(series.points.count) training days"
    }

    private static func makeMuscleGroupAccessibilityValue(_ groups: [LifterCoaching.MuscleGroupCoverage]) -> String {
        guard !groups.isEmpty else { return "No data" }
        let top = groups.prefix(3)
            .map { String(format: "%@ %.1f sets per week, %@", $0.category.displayName, $0.setsPerWeek, $0.band.label) }
            .joined(separator: ", ")
        return "Weekly sets by muscle group: \(top)"
    }

    private static func makeEffortAccessibilityValue(_ summaries: [TrendDailySummary], usesWeeks: Bool) -> String {
        let values = summaries.compactMap(\.averageRPE)
        guard !values.isEmpty else { return "No data" }
        let average = values.reduce(0, +) / Double(values.count)
        let bucketLabel = usesWeeks ? "weeks" : "days"
        return String(format: "Average effort RPE %.1f over %d active %@", average, values.count, bucketLabel)
    }

    // MARK: - Accessibility summaries
    // These mirror the strings the Trends charts expose via `.accessibilityValue`,
    // computed once during `build()` rather than re-reduced on every render.

    private static func makeConsistencyAccessibilityValue(_ data: [TrendDailySummary], usesWeeks: Bool) -> String {
        guard !data.isEmpty else { return "No data" }
        let totalSets = data.reduce(0) { $0 + $1.count }
        let activeBuckets = data.filter { $0.count > 0 }.count
        let bucketLabel = usesWeeks ? "active weeks" : "active days"
        return "\(totalSets) sets over \(activeBuckets) \(bucketLabel)"
    }

    private static func makeVolumeAccessibilityValue(_ data: [VolumeDatum]) -> String {
        guard !data.isEmpty else { return "No data" }
        let totals = Dictionary(grouping: data, by: \.series).mapValues { items in
            items.reduce(0.0) { $0 + $1.value }
        }
        let weekCount = Set(data.map(\.weekStart)).count
        let parts: [String] = [
            totals[.weighted].map { "Weighted \(Int($0))" },
            totals[.reps].map { "Reps \(Int($0))" },
            totals[.duration].map { "Duration \(Int($0)) minutes" }
        ].compactMap { $0 }
        let summary = parts.joined(separator: ", ")
        if summary.isEmpty {
            return "\(weekCount) weeks of volume"
        }
        return "\(summary) across \(weekCount) weeks"
    }

    private static func makeSupplementAccessibilityValue(
        _ data: [SupplementDailySummary],
        mode: SupplementTrendDisplayMode,
        usesWeeks: Bool
    ) -> String {
        guard !data.isEmpty else { return "No data" }
        let bucketLabel = usesWeeks ? "weeks" : "days"
        switch mode {
        case .dose(let unit):
            let total = data.reduce(0.0) { $0 + $1.totalDose }
            let formatted = Formatters.dose.string(from: NSNumber(value: total)) ?? "\(total)"
            let activeBuckets = data.filter { $0.count > 0 }.count
            return "Total \(formatted) \(unit.displayName) over \(activeBuckets) \(bucketLabel)"
        case .count:
            let total = data.reduce(0) { $0 + $1.count }
            let activeBuckets = data.filter { $0.count > 0 }.count
            return "\(total) logs over \(activeBuckets) \(bucketLabel)"
        }
    }

    /// Ranged modes fill empty buckets so the chart shows zero days/weeks;
    /// the all-time mode only includes buckets that contain data.
    private static func bucketSummaries<Entry>(
        groups: [Date: [Entry]],
        range: TrendRange,
        bucketStart: Date?,
        advance: (Date) -> Date?,
        now: Date
    ) -> [(Date, [Entry])] {
        if range == .all || bucketStart == nil {
            return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
        }

        var buckets: [(Date, [Entry])] = []
        var current = bucketStart ?? now
        while current <= now {
            buckets.append((current, groups[current] ?? []))
            guard let next = advance(current) else { break }
            current = next
        }
        return buckets
    }

    private static func resolveSupplementDisplayMode(
        entries: [SupplementEntry],
        selectedType: SupplementType?
    ) -> SupplementTrendDisplayMode {
        guard let selectedType else {
            return .count(reason: .allSupplements)
        }

        let unitsWithDose = Set(entries.compactMap { entry in
            entry.dose == nil ? nil : entry.unit
        })
        if unitsWithDose.count > 1 {
            return .count(reason: .mixedUnits)
        }
        if unitsWithDose.isEmpty {
            return .count(reason: .noDoseData)
        }
        return .dose(unit: unitsWithDose.first ?? selectedType.unit)
    }
}
