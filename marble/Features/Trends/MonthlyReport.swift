import Foundation

/// Pure engine behind the monthly training report: totals, PRs, muscle focus,
/// and honest month-over-month deltas. All arithmetic lives here — the
/// optional Apple Intelligence layer only phrases numbers this engine
/// already computed.
struct MonthlyReport: Equatable, Identifiable {
    var id: Date { monthStart }

    struct MuscleFocus: Identifiable, Equatable {
        let category: ExerciseCategory
        let sets: Int

        var id: ExerciseCategory { category }
    }

    let monthStart: Date
    /// e.g. "July 2026"
    let monthLabel: String
    /// True while the report describes the month still under way.
    let isMonthToDate: Bool

    let sessions: Int
    let sets: Int
    /// Σ weight × reps across weighted sets, kilogram-normalized.
    let volumeKilograms: Double
    let prCount: Int
    let averageRPE: Double?
    let topMuscleGroups: [MuscleFocus]

    // Deltas vs the previous month — compared through the SAME day of month
    // while the current month is under way ("vs this point in June"), so a
    // half-finished month is never judged against a full one. Nil when the
    // previous month has no data.
    let sessionsDelta: Int?
    let volumeDeltaPercent: Double?
    let prDelta: Int?
    /// e.g. "vs this point in June" / "vs June"
    let comparisonLabel: String?
}

enum MonthlyReportBuilder {
    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let monthOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    /// Builds the report for the month containing `now`, falling back to the
    /// previous month during its first days (a report about three days of
    /// data isn't a report). Returns nil when neither month has sets.
    static func build(
        history: [SetEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> MonthlyReport? {
        guard !history.isEmpty else { return nil }
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }

        let dayOfMonth = calendar.component(.day, from: now)
        let currentMonthEntries = entries(in: history, monthStart: currentMonthStart, calendar: calendar)

        // Early in a month, last month's completed story is the useful one.
        if dayOfMonth <= 5 || currentMonthEntries.isEmpty {
            if let previousStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart),
               let report = completedMonthReport(history: history, monthStart: previousStart, calendar: calendar) {
                return report
            }
        }

        guard !currentMonthEntries.isEmpty else { return nil }
        return monthToDateReport(
            history: history,
            monthStart: currentMonthStart,
            entries: currentMonthEntries,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Report assembly

    private static func completedMonthReport(
        history: [SetEntry],
        monthStart: Date,
        calendar: Calendar
    ) -> MonthlyReport? {
        let monthEntries = entries(in: history, monthStart: monthStart, calendar: calendar)
        guard !monthEntries.isEmpty else { return nil }

        let stats = MonthStats(entries: monthEntries, history: history, monthStart: monthStart, monthEnd: monthEnd(after: monthStart, calendar: calendar), calendar: calendar)

        var sessionsDelta: Int?
        var volumeDeltaPercent: Double?
        var prDelta: Int?
        var comparisonLabel: String?
        if let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            let previousEntries = entries(in: history, monthStart: previousStart, calendar: calendar)
            if !previousEntries.isEmpty {
                let previous = MonthStats(entries: previousEntries, history: history, monthStart: previousStart, monthEnd: monthEnd(after: previousStart, calendar: calendar), calendar: calendar)
                sessionsDelta = stats.sessions - previous.sessions
                volumeDeltaPercent = deltaPercent(current: stats.volumeKilograms, previous: previous.volumeKilograms)
                prDelta = stats.prCount - previous.prCount
                comparisonLabel = "vs \(monthOnlyFormatter.string(from: previousStart))"
            }
        }

        return MonthlyReport(
            monthStart: monthStart,
            monthLabel: monthLabelFormatter.string(from: monthStart),
            isMonthToDate: false,
            sessions: stats.sessions,
            sets: stats.sets,
            volumeKilograms: stats.volumeKilograms,
            prCount: stats.prCount,
            averageRPE: stats.averageRPE,
            topMuscleGroups: stats.topMuscleGroups,
            sessionsDelta: sessionsDelta,
            volumeDeltaPercent: volumeDeltaPercent,
            prDelta: prDelta,
            comparisonLabel: comparisonLabel
        )
    }

    private static func monthToDateReport(
        history: [SetEntry],
        monthStart: Date,
        entries monthEntries: [SetEntry],
        now: Date,
        calendar: Calendar
    ) -> MonthlyReport {
        let stats = MonthStats(entries: monthEntries, history: history, monthStart: monthStart, monthEnd: monthEnd(after: monthStart, calendar: calendar), calendar: calendar)

        var sessionsDelta: Int?
        var volumeDeltaPercent: Double?
        var prDelta: Int?
        var comparisonLabel: String?
        let dayOfMonth = calendar.component(.day, from: now)
        if let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            // Same-point comparison: previous month clipped to the same day count.
            let clipEnd = calendar.date(byAdding: .day, value: dayOfMonth, to: previousStart) ?? previousStart
            let previousEntries = entries(in: history, monthStart: previousStart, calendar: calendar)
                .filter { $0.performedAt < clipEnd }
            if !previousEntries.isEmpty {
                let previous = MonthStats(entries: previousEntries, history: history, monthStart: previousStart, monthEnd: clipEnd, calendar: calendar)
                sessionsDelta = stats.sessions - previous.sessions
                volumeDeltaPercent = deltaPercent(current: stats.volumeKilograms, previous: previous.volumeKilograms)
                prDelta = stats.prCount - previous.prCount
                comparisonLabel = "vs this point in \(monthOnlyFormatter.string(from: previousStart))"
            }
        }

        return MonthlyReport(
            monthStart: monthStart,
            monthLabel: monthLabelFormatter.string(from: monthStart),
            isMonthToDate: true,
            sessions: stats.sessions,
            sets: stats.sets,
            volumeKilograms: stats.volumeKilograms,
            prCount: stats.prCount,
            averageRPE: stats.averageRPE,
            topMuscleGroups: stats.topMuscleGroups,
            sessionsDelta: sessionsDelta,
            volumeDeltaPercent: volumeDeltaPercent,
            prDelta: prDelta,
            comparisonLabel: comparisonLabel
        )
    }

    // MARK: - Shared pieces

    private struct MonthStats {
        let sessions: Int
        let sets: Int
        let volumeKilograms: Double
        let prCount: Int
        let averageRPE: Double?
        let topMuscleGroups: [MonthlyReport.MuscleFocus]

        init(entries: [SetEntry], history: [SetEntry], monthStart: Date, monthEnd: Date, calendar: Calendar) {
            sessions = Set(entries.map { calendar.startOfDay(for: $0.performedAt) }).count
            sets = entries.count

            var volume = 0.0
            var rpeTotal = 0
            var muscleCounts: [ExerciseCategory: Int] = [:]
            let muscleCategories = Set(LifterAnalytics.muscleGroupCategories)
            for entry in entries {
                if let weight = entry.weight, let reps = entry.reps {
                    volume += PersonalRecords.kilograms(weight, unit: entry.weightUnit) * Double(reps)
                }
                rpeTotal += entry.difficulty
                if muscleCategories.contains(entry.exercise.category) {
                    muscleCounts[entry.exercise.category, default: 0] += 1
                }
            }
            volumeKilograms = volume
            averageRPE = entries.isEmpty ? nil : Double(rpeTotal) / Double(entries.count)

            topMuscleGroups = muscleCounts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key.displayName < rhs.key.displayName }
                    return lhs.value > rhs.value
                }
                .prefix(3)
                .map { MonthlyReport.MuscleFocus(category: $0.key, sets: $0.value) }

            // Real record-breaking sets inside the month (baselines and early
            // noise already excluded by the feed's rules).
            prCount = LifterCoaching.prEvents(history: history, rangeStart: nil, selectedExerciseID: nil, calendar: calendar)
                .filter { $0.date >= monthStart && $0.date < monthEnd }
                .count
        }
    }

    private static func entries(in history: [SetEntry], monthStart: Date, calendar: Calendar) -> [SetEntry] {
        let end = monthEnd(after: monthStart, calendar: calendar)
        return history.filter { $0.performedAt >= monthStart && $0.performedAt < end }
    }

    private static func monthEnd(after monthStart: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    private static func deltaPercent(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }
}
