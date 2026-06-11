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

    static func build(
        entries: [SetEntry],
        supplementEntries: [SupplementEntry],
        selectedExercise: Exercise?,
        selectedSupplementType: SupplementType?,
        range: TrendRange,
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
            liftBests: selectedExercise.flatMap { ExerciseProgressBuilder.buildLiftBests(entries: filteredEntries, exercise: $0, range: range) }
        )
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
