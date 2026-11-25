import Foundation

// Pure, unit-tested inputs for the redesigned Progress Details visuals: the
// Pulse card's period-over-period deltas and the consistency heatmap. Both are
// derived once in `TrendsDerivedData.build()` and memoized with it.

/// Change versus the equal-length window immediately before the selected
/// range ("last 30 days" vs "the 30 days before that"). `nil` for All Time,
/// which has no previous window.
struct TrendsPeriodComparison: Equatable {
    let currentSets: Int
    let previousSets: Int
    /// Weight × reps, summed in kilograms (unit-normalized like the volume chart).
    let currentVolumeKilograms: Double
    let previousVolumeKilograms: Double
    let currentActiveDays: Int
    let previousActiveDays: Int

    var setsChangePercent: Double? { Self.percentChange(Double(currentSets), from: Double(previousSets)) }
    var volumeChangePercent: Double? { Self.percentChange(currentVolumeKilograms, from: previousVolumeKilograms) }
    var activeDaysChangePercent: Double? { Self.percentChange(Double(currentActiveDays), from: Double(previousActiveDays)) }

    /// `nil` when there is nothing to compare against — a percentage over an
    /// empty previous period is noise, not insight.
    static func percentChange(_ current: Double, from previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    /// - Parameters:
    ///   - history: every set the lifter has logged (unfiltered by range).
    ///   - currentEntries: the range-filtered sets already computed by the caller.
    ///   - rangeStart: start of the selected range; `nil` (All Time) returns `nil`.
    static func make(
        history: [SetEntry],
        currentEntries: [SetEntry],
        selectedExerciseID: UUID?,
        rangeStart: Date?,
        now: Date,
        calendar: Calendar
    ) -> TrendsPeriodComparison? {
        guard let rangeStart else { return nil }
        let start = calendar.startOfDay(for: rangeStart)
        let today = calendar.startOfDay(for: now)
        let spanDays = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        guard spanDays > 0,
              let previousStart = calendar.date(byAdding: .day, value: -spanDays, to: start)
        else { return nil }

        var previousSets = 0
        var previousVolume: Double = 0
        var previousDays = Set<Date>()
        for entry in history {
            if let selectedExerciseID, entry.exercise.id != selectedExerciseID { continue }
            guard entry.performedAt >= previousStart, entry.performedAt < start else { continue }
            previousSets += 1
            previousVolume += weightedVolumeKilograms(entry)
            previousDays.insert(calendar.startOfDay(for: entry.performedAt))
        }

        var currentVolume: Double = 0
        var currentDays = Set<Date>()
        for entry in currentEntries {
            currentVolume += weightedVolumeKilograms(entry)
            currentDays.insert(calendar.startOfDay(for: entry.performedAt))
        }

        return TrendsPeriodComparison(
            currentSets: currentEntries.count,
            previousSets: previousSets,
            currentVolumeKilograms: currentVolume,
            previousVolumeKilograms: previousVolume,
            currentActiveDays: currentDays.count,
            previousActiveDays: previousDays.count
        )
    }

    static func weightedVolumeKilograms(_ entry: SetEntry) -> Double {
        guard let weight = entry.weight, let reps = entry.reps else { return 0 }
        return PersonalRecords.kilograms(weight, unit: entry.weightUnit) * Double(reps)
    }
}

/// One square per calendar day across the selected range, with a 0–4
/// intensity level, PR marks, and the streak/weekday facts shown beneath it.
struct TrendsHeatmapModel: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        let count: Int
        /// 0 = rest day; 1…4 = quartiles of the busiest day in range.
        let level: Int
        let hasPR: Bool
        let isToday: Bool

        var id: Date { date }
    }

    static let levelCount = 4

    /// Contiguous, oldest first; always ends today.
    let days: [Day]
    let maxCount: Int
    let activeDays: Int
    let longestStreak: Int
    let currentStreak: Int
    /// `Calendar` weekday (1 = Sunday) with the most active days, if any.
    let busiestWeekday: Int?

    var first: Date? { days.first?.date }
    var last: Date? { days.last?.date }

    func day(for date: Date, calendar: Calendar) -> Day? {
        let key = calendar.startOfDay(for: date)
        return days.first { $0.date == key }
    }

    static func level(count: Int, maxCount: Int) -> Int {
        guard count > 0, maxCount > 0 else { return 0 }
        let ratio = Double(count) / Double(maxCount)
        return min(levelCount, max(1, Int((ratio * Double(levelCount)).rounded(.up))))
    }

    /// - Parameters:
    ///   - dayCounts: sets per start-of-day.
    ///   - prDays: start-of-day dates that hold at least one PR.
    ///   - rangeStart: first day to draw; `nil` (All Time) starts at the
    ///     earliest logged day, capped to `maximumDays` back from today.
    static func make(
        dayCounts: [Date: Int],
        prDays: Set<Date>,
        rangeStart: Date?,
        now: Date,
        calendar: Calendar,
        maximumDays: Int = 371
    ) -> TrendsHeatmapModel {
        let today = calendar.startOfDay(for: now)
        let earliestAllowed = calendar.date(byAdding: .day, value: -(maximumDays - 1), to: today) ?? today
        let proposedStart = rangeStart.map { calendar.startOfDay(for: $0) }
            ?? dayCounts.keys.min()
            ?? today
        let start = max(min(proposedStart, today), earliestAllowed)

        let maxCount = dayCounts.compactMap { date, count in
            date >= start && date <= today ? count : nil
        }.max() ?? 0

        var days: [Day] = []
        var cursor = start
        var running = 0
        var longest = 0
        var weekdayTotals: [Int: Int] = [:]
        while cursor <= today {
            let count = dayCounts[cursor] ?? 0
            if count > 0 {
                running += 1
                longest = max(longest, running)
                weekdayTotals[calendar.component(.weekday, from: cursor), default: 0] += 1
            } else {
                running = 0
            }
            days.append(Day(
                date: cursor,
                count: count,
                level: level(count: count, maxCount: maxCount),
                hasPR: prDays.contains(cursor),
                isToday: cursor == today
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // A streak survives a rest day *today*: it is only broken once a
        // full day passes without training.
        var current = 0
        for (offset, day) in days.reversed().enumerated() {
            if day.count > 0 {
                current += 1
            } else if offset == 0 {
                continue
            } else {
                break
            }
        }

        let busiest = weekdayTotals.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key

        return TrendsHeatmapModel(
            days: days,
            maxCount: maxCount,
            activeDays: days.filter { $0.count > 0 }.count,
            longestStreak: longest,
            currentStreak: current,
            busiestWeekday: busiest
        )
    }
}
