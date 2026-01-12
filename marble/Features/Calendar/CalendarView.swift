import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var selectedComponents: DateComponents?
    @State private var isShowingDaySheet = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack {
                CalendarRepresentable(decorations: dayDecorations) { components in
                    selectedComponents = components
                    isShowingDaySheet = components != nil
                }
                .frame(maxHeight: 360)

                Spacer()
            }
            .padding(.horizontal, 12)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .sheet(isPresented: $isShowingDaySheet) {
                if let date = selectedDate {
                    DaySummarySheet(date: date, entries: entriesForSelectedDay)
                        .environmentObject(quickLog)
                }
            }
        }
    }

    private var dayDecorations: [DateComponents: Int] {
        var counts: [DateComponents: Int] = [:]
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.performedAt)
        }
        for (day, dayEntries) in grouped {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let count = dayEntries.count
            let tier: Int
            switch count {
            case 0:
                tier = 0
            case 1:
                tier = 1
            case 2...4:
                tier = 2
            default:
                tier = 3
            }
            counts[components] = tier
        }
        return counts
    }

    private var selectedDate: Date? {
        guard let components = selectedComponents else { return nil }
        return calendar.date(from: components)
    }

    private var entriesForSelectedDay: [SetEntry] {
        guard let date = selectedDate else { return [] }
        let start = calendar.startOfDay(for: date)
        return entries.filter { calendar.isDate($0.performedAt, inSameDayAs: start) }
    }
}

struct DaySummarySheet: View {
    let date: Date
    let entries: [SetEntry]

    @EnvironmentObject private var quickLog: QuickLogCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(DateHelper.dayLabel(for: date))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text("\(entries.count) sets · \(uniqueExerciseCount) exercises · Avg RPE \(averageRPE)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        Button("Log Set for this day") {
                            quickLog.open(prefillDate: date)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                Section("Sets") {
                    ForEach(entries.sorted { $0.performedAt > $1.performedAt }) { entry in
                        NavigationLink {
                            SetDetailView(entry: entry)
                        } label: {
                            SetRowView(entry: entry)
                        }
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
        }
    }

    private var uniqueExerciseCount: Int {
        Set(entries.map { $0.exercise.id }).count
    }

    private var averageRPE: String {
        guard !entries.isEmpty else { return "-" }
        let total = entries.reduce(0) { $0 + $1.difficulty }
        let avg = Double(total) / Double(entries.count)
        return String(format: "%.1f", avg)
    }
}

struct CalendarRepresentable: UIViewRepresentable {
    var decorations: [DateComponents: Int]
    var onSelect: (DateComponents?) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.locale = Locale.current
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.decorations = decorations
        let keys = Array(decorations.keys)
        uiView.reloadDecorations(forDateComponents: keys, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, decorations: decorations)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        let onSelect: (DateComponents?) -> Void
        var decorations: [DateComponents: Int]

        init(onSelect: @escaping (DateComponents?) -> Void, decorations: [DateComponents: Int]) {
            self.onSelect = onSelect
            self.decorations = decorations
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let tier = decorations[dateComponents], tier > 0 else {
                return nil
            }
            let image = CalendarDecoration.image(forTier: tier)
            return .image(image)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            onSelect(dateComponents)
        }

        private func dateSelection(_ selection: UICalendarSelectionSingleDate, didDeselectDate dateComponents: DateComponents?) {
            onSelect(nil)
        }
    }
}

enum CalendarDecoration {
    static func image(forTier tier: Int) -> UIImage {
        let count = min(max(tier, 1), 3)
        let size = CGSize(width: 18, height: 6)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let dotSize: CGFloat = 4
            let spacing: CGFloat = 2
            let totalWidth = CGFloat(count) * dotSize + CGFloat(count - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            let y = (size.height - dotSize) / 2
            let color = UIColor(white: 0.5, alpha: 1.0)
            for index in 0..<count {
                let x = startX + CGFloat(index) * (dotSize + spacing)
                let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.fillEllipse(in: rect)
            }
        }
    }
}
