import SwiftUI
import SwiftData

struct SupplementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SupplementEntry.takenAt, order: .reverse)
    private var entries: [SupplementEntry]

    @Query(sort: \SupplementType.name)
    private var types: [SupplementType]

    @State private var toast: ToastData?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quickAddRow
                }

                ForEach(sectionedDays, id: \.self) { day in
                    if let dayEntries = groupedEntries[day] {
                        Section(DateHelper.dayLabel(for: day)) {
                            ForEach(dayEntries) { entry in
                                NavigationLink {
                                    SupplementDetailView(entry: entry)
                                } label: {
                                    SupplementRowView(entry: entry)
                                }
                                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SupplementTypeManagerView()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
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

    private var groupedEntries: [Date: [SupplementEntry]] {
        Dictionary(grouping: entries) { entry in
            DateHelper.startOfDay(for: entry.takenAt)
        }.mapValues { dayEntries in
            dayEntries.sorted { $0.takenAt > $1.takenAt }
        }
    }

    private var sectionedDays: [Date] {
        groupedEntries.keys.sorted(by: >)
    }

    private var quickTypes: [SupplementType] {
        let names = ["Creatine", "Protein Powder"]
        return types.filter { names.contains($0.name) }
    }

    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            HStack(spacing: 12) {
                ForEach(quickTypes) { type in
                    Button(type.name) {
                        quickAdd(type)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.primaryTextColor(for: colorScheme))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func quickAdd(_ type: SupplementType) {
        let entry = SupplementEntry(
            type: type,
            takenAt: Date(),
            dose: type.defaultDose,
            unit: type.unit,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        modelContext.insert(entry)
        toast = ToastData(message: "Logged \(type.name)", actionTitle: "Undo") {
            undoQuickAdd(entry)
        }
    }

    private func delete(_ entry: SupplementEntry) {
        let snapshot = SupplementEntrySnapshot(entry: entry)
        modelContext.delete(entry)
        toast = ToastData(message: "Entry deleted", actionTitle: "Undo") {
            undoDelete(snapshot)
        }
    }

    private func undoDelete(_ snapshot: SupplementEntrySnapshot) {
        snapshot.restore(in: modelContext)
        toast = nil
    }

    private func undoQuickAdd(_ entry: SupplementEntry) {
        modelContext.delete(entry)
        toast = nil
    }
}

private struct ToastData {
    let message: String
    let actionTitle: String?
    let onAction: (() -> Void)?
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
