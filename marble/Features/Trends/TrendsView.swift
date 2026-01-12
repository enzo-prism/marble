import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var range: TrendRange = .thirtyDays
    @State private var selectedExercise: Exercise?
    @State private var selectedDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rangePicker
                    exercisePicker

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Consistency")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        consistencyChart
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Weekly Volume")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        volumeChart
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRs")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        prCards
                    }
                }
                .padding(16)
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
        }
    }

    private var filteredEntries: [SetEntry] {
        var filtered = entries
        if let selectedExercise {
            filtered = filtered.filter { $0.exercise == selectedExercise }
        }
        if let startDate = range.startDate {
            filtered = filtered.filter { $0.performedAt >= startDate }
        }
        return filtered
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var exercisePicker: some View {
        Picker("Exercise", selection: $selectedExercise) {
            Text("All Exercises").tag(Exercise?.none)
            ForEach(exercises) { exercise in
                Text(exercise.name).tag(exercise as Exercise?)
            }
        }
        .pickerStyle(.menu)
    }

    private var consistencyChart: some View {
        let data = consistencyData
        return Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Day", item.date),
                    y: .value("Sets", item.count)
                )
                .foregroundStyle(Color(white: 0.6))
            }

            if let selectedDay, let selectedItem = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }) {
                RuleMark(x: .value("Selected", selectedItem.date))
                    .foregroundStyle(Color(white: 0.3))
                    .annotation(position: .top) {
                        Text("\(selectedItem.count) sets")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDay = nearestDay(to: date, in: data)
                                }
                            }
                            .onEnded { _ in
                                selectedDay = nil
                            }
                    )
            }
        }
    }

    private var volumeChart: some View {
        let data = volumeData
        return Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Week", item.weekStart),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(item.series.color)
                .position(by: .value("Series", item.series.label))
            }
        }
        .frame(height: 180)
        .chartLegend(position: .bottom, alignment: .leading)
    }

    private var prCards: some View {
        let bestWeightEntry = filteredEntries
            .filter { $0.weight != nil }
            .max { (lhs, rhs) in
                (lhs.weight ?? 0) < (rhs.weight ?? 0)
            }
        let bestReps = filteredEntries.compactMap { $0.reps }.max()
        let bestDuration = filteredEntries.compactMap { $0.durationSeconds }.max()

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                PRCardView(
                    title: "Best Weight",
                    value: bestWeightEntry.map {
                        let formatted = Formatters.weight.string(from: NSNumber(value: $0.weight ?? 0)) ?? "\($0.weight ?? 0)"
                        return "\(formatted) \($0.weightUnit.symbol)"
                    } ?? "-"
                )
                PRCardView(title: "Best Reps", value: bestReps.map { "\($0) reps" } ?? "-")
            }
            HStack(spacing: 12) {
                PRCardView(title: "Longest Duration", value: bestDuration.map { DateHelper.formattedDuration(seconds: $0) } ?? "-")
                PRCardView(title: "Sessions", value: "\(Set(filteredEntries.map { DateHelper.startOfDay(for: $0.performedAt) }).count)")
            }
        }
    }

    private var consistencyData: [DailyCount] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.performedAt)
        }

        if range == .all {
            return grouped.keys.sorted().map { day in
                DailyCount(date: day, count: grouped[day]?.count ?? 0)
            }
        }

        guard let startDate = range.startDate else { return [] }
        let endDate = calendar.startOfDay(for: Date())
        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates.map { day in
            DailyCount(date: day, count: grouped[day]?.count ?? 0)
        }
    }

    private var volumeData: [VolumeDatum] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry -> Date in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.performedAt)
            return calendar.date(from: components) ?? calendar.startOfDay(for: entry.performedAt)
        }

        var data: [VolumeDatum] = []
        for (weekStart, items) in grouped {
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

            if weightedVolume > 0 {
                data.append(VolumeDatum(weekStart: weekStart, series: .weighted, value: weightedVolume))
            }
            if repsVolume > 0 {
                data.append(VolumeDatum(weekStart: weekStart, series: .reps, value: Double(repsVolume)))
            }
            if durationSeconds > 0 {
                data.append(VolumeDatum(weekStart: weekStart, series: .duration, value: Double(durationSeconds) / 60.0))
            }
        }

        return data.sorted { $0.weekStart < $1.weekStart }
    }

    private func nearestDay(to date: Date, in data: [DailyCount]) -> Date? {
        guard !data.isEmpty else { return nil }
        let target = Calendar.current.startOfDay(for: date)
        return data.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })?.date
    }
}

struct DailyCount: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

struct VolumeDatum: Identifiable {
    let weekStart: Date
    let series: VolumeSeries
    let value: Double

    var id: String { "\(weekStart.timeIntervalSince1970)-\(series.rawValue)" }
}

enum VolumeSeries: String, CaseIterable {
    case weighted
    case reps
    case duration

    var label: String {
        switch self {
        case .weighted:
            return "Weight x Reps"
        case .reps:
            return "Bodyweight Reps"
        case .duration:
            return "Duration (min)"
        }
    }

    var color: Color {
        switch self {
        case .weighted:
            return Color(white: 0.6)
        case .reps:
            return Color(white: 0.4)
        case .duration:
            return Color(white: 0.75)
        }
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sevenDays:
            return "7D"
        case .thirtyDays:
            return "30D"
        case .ninetyDays:
            return "90D"
        case .oneYear:
            return "1Y"
        case .all:
            return "All"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: Date()))
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: Date()))
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: Date()))
        case .all:
            return nil
        }
    }
}
