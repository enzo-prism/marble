import Foundation
import SwiftData

struct TrendDailySummary: Identifiable {
    let date: Date
    let entries: [SetEntry]

    var id: Date { date }
    var count: Int { entries.count }
    var uniqueExerciseCount: Int { Set(entries.map { $0.exercise.id }).count }
    var averageRPE: Double? {
        guard !entries.isEmpty else { return nil }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        return Double(total) / Double(entries.count)
    }

    var averageRPEText: String {
        guard let averageRPE else { return "-" }
        return String(format: "%.1f", averageRPE)
    }

    var summaryText: String {
        "\(count) sets · \(uniqueExerciseCount) exercises · Avg RPE \(averageRPEText)"
    }
}

struct TrendWeeklySummary: Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let entries: [SetEntry]
    let weightedVolume: Double
    let repsVolume: Int
    let durationMinutes: Double
    let maxSeriesValue: Double

    var id: Date { weekStart }
    var setCount: Int { entries.count }
    var uniqueExerciseCount: Int { Set(entries.map { $0.exercise.id }).count }
    var totalVolumeScore: Double { weightedVolume + Double(repsVolume) + durationMinutes }
    var averageRPE: Double? {
        guard !entries.isEmpty else { return nil }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        return Double(total) / Double(entries.count)
    }

    var averageRPEText: String {
        guard let averageRPE else { return "-" }
        return String(format: "%.1f", averageRPE)
    }

    var summaryText: String {
        "\(setCount) sets · \(uniqueExerciseCount) exercises · Avg RPE \(averageRPEText)"
    }

    var valueText: String {
        var parts: [String] = []
        if weightedVolume > 0 {
            let formatted = Formatters.weight.string(from: NSNumber(value: weightedVolume)) ?? "\(Int(weightedVolume))"
            parts.append("Weight x Reps \(formatted)")
        }
        if repsVolume > 0 {
            parts.append("Reps \(repsVolume)")
        }
        if durationMinutes > 0 {
            let formattedMinutes: String
            if durationMinutes.rounded() == durationMinutes {
                formattedMinutes = "\(Int(durationMinutes))m"
            } else {
                formattedMinutes = String(format: "%.1fm", durationMinutes)
            }
            parts.append("Duration \(formattedMinutes)")
        }
        return parts.isEmpty ? "No volume" : parts.joined(separator: " · ")
    }
}

enum TrendsDateHelper {
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func endOfWeek(for weekStart: Date, calendar: Calendar = .current) -> Date {
        guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return weekStart
        }
        return calendar.startOfDay(for: end)
    }

    static func weekLabel(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let formatter = startYear == endYear ? monthDayFormatter : monthDayYearFormatter
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)
        return "\(startText) - \(endText)"
    }
}
