import SwiftUI
import SwiftData

/// The weigh-in recorded on one calendar day, shown inside the Calendar day
/// summary — the 2.4 "weight on day" item.
///
/// Day-scoped at `init` like `ProgressMediaSection`, so opening a day sheet
/// fetches at most that day's rows rather than the whole bodyweight table.
/// Renders nothing on a day with no weigh-in: the day sheet is a record of what
/// happened, not a prompt.
struct DayBodyweightSection: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    @Query private var entries: [BodyMetricEntry]

    @State private var editingEntry: BodyMetricEntry?

    init(date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _entries = Query(
            filter: #Predicate<BodyMetricEntry> {
                $0.measuredAt >= dayStart && $0.measuredAt < dayEnd
            },
            sort: \BodyMetricEntry.measuredAt,
            order: .reverse
        )
    }

    private var displayUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    /// Last weigh-in of the day wins, matching the one-point-per-day rule the
    /// bodyweight chart uses.
    private var entry: BodyMetricEntry? { entries.first }

    var body: some View {
        if let entry {
            Section {
                Button {
                    editingEntry = entry
                } label: {
                    HStack(spacing: MarbleLayout.rowSpacing) {
                        Image(systemName: "scalemass")
                            .frame(width: MarbleLayout.rowIconSize)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                            Text(weightText(entry))
                                .font(MarbleTypography.rowTitle)
                                .monospacedDigit()
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Text(metaText(entry))
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .marbleRowInsets()
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .accessibilityLabel("Bodyweight \(weightText(entry))")
                .accessibilityValue(metaText(entry))
                .accessibilityHint("Edit this weigh-in")
                .accessibilityIdentifier("Calendar.DaySheet.Bodyweight")
            } header: {
                SectionHeaderView(title: "Bodyweight")
            }
            .textCase(nil)
            .sheet(item: $editingEntry) { entry in
                BodyMetricEntryView(entry: entry)
            }
        }
    }

    private func weightText(_ entry: BodyMetricEntry) -> String {
        let value = entry.displayWeight(in: displayUnit)
        let text = Formatters.weight.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(text) \(displayUnit.symbol)"
    }

    private func metaText(_ entry: BodyMetricEntry) -> String {
        var parts = [entry.measuredAt.formatted(date: .omitted, time: .shortened)]
        if let bodyFat = entry.bodyFatPercent {
            let text = Formatters.weight.string(from: NSNumber(value: bodyFat)) ?? "\(Int(bodyFat))"
            parts.append("\(text)% body fat")
        }
        if entry.source == .healthKit {
            parts.append(BodyMetricSource.healthKit.displayName)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
