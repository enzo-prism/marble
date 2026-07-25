import SwiftUI
import SwiftData

/// Every weigh-in, newest first — the surface that makes a bodyweight entry
/// *correctable*.
///
/// Before this existed, `BodyMetricEntryView` was only ever presented with
/// `entry: nil`, so its complete edit path had no caller: a typo'd weigh-in was
/// permanent, and it skewed both the bodyweight chart and every DOTS score
/// derived from it. Tapping a row here opens that same editor with the row's
/// entry; a trailing swipe deletes it.
///
/// Health-imported rows are editable too. Editing one flips its `source` to
/// `.manual` (the editor does that) while keeping `healthKitUUID`, so a later
/// re-import still dedups against it instead of resurrecting the bad number.
///
/// Embeds its own `NavigationStack` so it drops straight into a `.sheet { }`.
struct BodyMetricHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    /// Unbounded on purpose: this is the "all of my weigh-ins" screen, and it is
    /// only reachable behind a tap. The chart keeps its range-scoped query.
    @Query(sort: \BodyMetricEntry.measuredAt, order: .reverse)
    private var entries: [BodyMetricEntry]

    @State private var editingEntry: BodyMetricEntry?
    @State private var isPresentingNewEntry = false

    private var displayUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        title: "No weigh-ins yet",
                        message: "Log your bodyweight to build a trend — and to unlock relative strength on your lifts.",
                        systemImage: "figure.stand"
                    )
                    .accessibilityIdentifier("BodyMetricHistory.EmptyState")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Weigh-Ins")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("BodyMetricHistory.Done")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log weight")
                    .accessibilityIdentifier("BodyMetricHistory.Add")
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            BodyMetricEntryView(entry: entry)
        }
        .sheet(isPresented: $isPresentingNewEntry) {
            BodyMetricEntryView()
        }
    }

    private var list: some View {
        List {
            ForEach(entries) { entry in
                row(entry)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("BodyMetricHistory.List")
    }

    private func row(_ entry: BodyMetricEntry) -> some View {
        // Identifiers go on the row (a leaf Button) and on its swipe action —
        // never on the List or the inner VStack, which would override them.
        Button {
            editingEntry = entry
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.destructiveActionColor(for: colorScheme))
            .accessibilityIdentifier("BodyMetricHistory.Row.\(entry.id.uuidString).Delete")
        }
        .accessibilityIdentifier("BodyMetricHistory.Row.\(entry.id.uuidString)")
        .accessibilityLabel(weightText(entry))
        .accessibilityValue(metaText(entry))
        .accessibilityHint("Edit this weigh-in")
    }

    // MARK: - Text

    private func weightText(_ entry: BodyMetricEntry) -> String {
        let value = entry.displayWeight(in: displayUnit)
        let text = Formatters.weight.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(text) \(displayUnit.symbol)"
    }

    private func metaText(_ entry: BodyMetricEntry) -> String {
        var parts = [entry.measuredAt.formatted(date: .abbreviated, time: .shortened)]
        if let bodyFat = entry.bodyFatPercent {
            let text = Formatters.weight.string(from: NSNumber(value: bodyFat)) ?? "\(Int(bodyFat))"
            parts.append("\(text)% body fat")
        }
        if entry.source == .healthKit {
            parts.append(BodyMetricSource.healthKit.displayName)
        }
        if let notes = entry.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Delete

    private func delete(_ entry: BodyMetricEntry) {
        modelContext.delete(entry)
        if modelContext.saveOrRollback() {
            MarbleHaptics.lightImpact()
        }
    }
}

#Preview {
    BodyMetricHistoryView()
}
