import SwiftUI
import SwiftData

struct SupplementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SupplementEntry.takenAt, order: .reverse)
    private var entries: [SupplementEntry]

    @Query(sort: \SupplementType.name)
    private var types: [SupplementType]

    /// One-row freshness probe for the memo signature (see LatestUpdateQueries).
    @Query(LatestUpdateQueries.supplementEntry)
    private var latestUpdatedEntries: [SupplementEntry]

    @State private var toast: ToastData?

    // Day-grouping the full history is memoized (same pattern as Journal) so
    // unrelated state changes — a toast appearing, a sheet opening — don't
    // re-group and re-sort every entry on each body evaluation.
    @State private var derivedMemo = RenderMemo<SupplementsSignature, SupplementsDerived>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quickAddRow
                        .marbleRowInsets()
                }

                if entries.isEmpty {
                    EmptyStateView(title: "No supplements yet", message: "Log a quick add to get started.", systemImage: "pills")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("Supplements.EmptyState")
                }

                ForEach(sectionedDays, id: \.self) { day in
                    if let dayEntries = groupedEntries[day] {
                        Section {
                            ForEach(dayEntries) { entry in
                                let sanitizedName = entry.type.name.replacingOccurrences(of: " ", with: "")
                                NavigationLink {
                                    SupplementDetailView(entry: entry)
                                } label: {
                                    SupplementRowView(entry: entry)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("SupplementRow.\(sanitizedName)")
                                .accessibilityLabel(SupplementRowView.accessibilityLabel(for: entry))
                                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                                .marbleRowInsets()
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(Theme.destructiveActionColor(for: colorScheme))
                                }
                            }
                        } header: {
                            SectionHeaderView(title: DateHelper.dayLabel(for: day))
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .contentMargins(.top, MarbleSpacing.xs, for: .scrollContent)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Supplements.List")
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SupplementTypeManagerView()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Manage Supplement Types")
                    .accessibilityIdentifier("Supplements.ManageTypes")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(
                        message: toast.message,
                        actionTitle: toast.actionTitle,
                        onAction: toast.onAction,
                        onDismiss: { self.toast = nil }
                    )
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var derived: SupplementsDerived {
        let signature = SupplementsSignature(
            count: entries.count,
            latestUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast
        )
        return derivedMemo.value(for: signature) {
            // Entries arrive sorted newest-first from the query, so grouping
            // preserves in-day order without a per-day re-sort.
            let grouped = Dictionary(grouping: entries) { entry in
                DateHelper.startOfDay(for: entry.takenAt)
            }
            return SupplementsDerived(
                groupedEntries: grouped,
                sectionedDays: grouped.keys.sorted(by: >)
            )
        }
    }

    private var groupedEntries: [Date: [SupplementEntry]] {
        derived.groupedEntries
    }

    private var sectionedDays: [Date] {
        derived.sectionedDays
    }

    private var quickTypes: [SupplementType] {
        let names = ["Creatine", "Protein Powder"]
        return types.filter { names.contains($0.name) }
    }

    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            HStack(spacing: 12) {
                ForEach(quickTypes) { type in
                    Button {
                        quickAdd(type)
                    } label: {
                        MarbleChipLabel(title: type.name, isSelected: false, isDisabled: false, isExpanded: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Supplements.QuickAdd.\(type.name.replacingOccurrences(of: " ", with: ""))")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func quickAdd(_ type: SupplementType) {
        let now = AppEnvironment.now
        let entry = SupplementEntry(
            type: type,
            takenAt: now,
            dose: type.defaultDose,
            unit: type.unit,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(entry)
        guard modelContext.saveOrRollback() else {
            toast = ToastData(message: "Couldn't log \(type.name)", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.success()
        toast = ToastData(message: "Logged \(type.name)", actionTitle: "Undo") {
            undoQuickAdd(entry)
        }
    }

    private func delete(_ entry: SupplementEntry) {
        let snapshot = SupplementEntrySnapshot(entry: entry)
        modelContext.delete(entry)
        guard modelContext.saveOrRollback() else {
            toast = ToastData(message: "Couldn't delete entry", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.warning()
        toast = ToastData(message: "Entry deleted", actionTitle: "Undo") {
            undoDelete(snapshot)
        }
    }

    private func undoDelete(_ snapshot: SupplementEntrySnapshot) {
        snapshot.restore(in: modelContext)
        if modelContext.saveOrRollback() {
            MarbleHaptics.lightImpact()
        }
        toast = nil
    }

    private func undoQuickAdd(_ entry: SupplementEntry) {
        modelContext.delete(entry)
        if modelContext.saveOrRollback() {
            MarbleHaptics.lightImpact()
        }
        toast = nil
    }
}

private struct ToastData {
    let message: String
    let actionTitle: String?
    let onAction: (() -> Void)?
}

/// Memoized supplements derivations: entries grouped per day plus the sorted
/// day list, computed once per data change instead of per body evaluation.
private struct SupplementsDerived {
    let groupedEntries: [Date: [SupplementEntry]]
    let sectionedDays: [Date]
}

/// Cheap `Equatable` fingerprint: the count catches inserts/deletes, the
/// one-row `updatedAt` probe catches in-place edits.
private struct SupplementsSignature: Equatable {
    let count: Int
    let latestUpdate: Date
}

private struct SupplementEntrySnapshot {
    let id: UUID
    let type: SupplementType
    let takenAt: Date
    let dose: Double?
    let unit: SupplementUnit
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    init(entry: SupplementEntry) {
        id = entry.id
        type = entry.type
        takenAt = entry.takenAt
        dose = entry.dose
        unit = entry.unit
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func restore(in context: ModelContext) {
        let restored = SupplementEntry(
            id: id,
            type: type,
            takenAt: takenAt,
            dose: dose,
            unit: unit,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        context.insert(restored)
    }
}
