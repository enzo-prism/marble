import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var toast: ToastData?
    @State private var pendingUndo: SetEntrySnapshot?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    EmptyStateView(title: "No sets yet", message: "Log your first set to start building momentum.", systemImage: "list.bullet.rectangle")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("Journal.EmptyState")
                }
                ForEach(sectionedDays, id: \.self) { day in
                    if let dayEntries = groupedEntries[day] {
                        Section {
                            ForEach(dayEntries) { entry in
                                NavigationLink {
                                    SetDetailView(entry: entry)
                                } label: {
                                    SetRowView(entry: entry)
                                        .accessibilityHidden(true)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
                                .accessibilityLabel(SetRowView.accessibilitySummary(for: entry))
                                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                                .marbleRowInsets()
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        duplicate(entry)
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .accessibilityIdentifier("SetRow.\(entry.id.uuidString).Duplicate")
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("SetRow.\(entry.id.uuidString).Delete")
                                }
                            }
                        } header: {
                            SectionHeaderView(title: DateHelper.dayLabel(for: day))
                        }
                        .textCase(nil)
                        .listRowSeparator(.visible)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Journal.List")
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarGlassBackground()
            .toolbar {
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

    private var groupedEntries: [Date: [SetEntry]] {
        Dictionary(grouping: entries) { entry in
            DateHelper.startOfDay(for: entry.performedAt)
        }.mapValues { dayEntries in
            dayEntries.sorted { $0.performedAt > $1.performedAt }
        }
    }

    private var sectionedDays: [Date] {
        groupedEntries.keys.sorted(by: >)
    }

    private func delete(_ entry: SetEntry) {
        let snapshot = SetEntrySnapshot(entry: entry)
        modelContext.delete(entry)
        pendingUndo = snapshot
        toast = ToastData(message: "Set deleted", actionTitle: "Undo") {
            undoDelete()
        }
    }

    private func undoDelete() {
        guard let snapshot = pendingUndo else { return }
        snapshot.restore(in: modelContext)
        pendingUndo = nil
        toast = nil
    }

    private func duplicate(_ entry: SetEntry) {
        let now = AppEnvironment.now
        let duplicate = SetEntry(
            exercise: entry.exercise,
            performedAt: now,
            weight: entry.weight,
            weightUnit: entry.weightUnit,
            reps: entry.reps,
            durationSeconds: entry.durationSeconds,
            difficulty: entry.difficulty,
            restAfterSeconds: entry.restAfterSeconds,
            notes: entry.notes,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(duplicate)
    }
}

private struct ToastData {
    let message: String
    let actionTitle: String?
    let onAction: (() -> Void)?
}

private struct SetEntrySnapshot {
    let id: UUID
    let exercise: Exercise
    let performedAt: Date
    let weight: Double?
    let weightUnit: WeightUnit
    let reps: Int?
    let durationSeconds: Int?
    let difficulty: Int
    let restAfterSeconds: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    init(entry: SetEntry) {
        id = entry.id
        exercise = entry.exercise
        performedAt = entry.performedAt
        weight = entry.weight
        weightUnit = entry.weightUnit
        reps = entry.reps
        durationSeconds = entry.durationSeconds
        difficulty = entry.difficulty
        restAfterSeconds = entry.restAfterSeconds
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func restore(in context: ModelContext) {
        let restored = SetEntry(
            id: id,
            exercise: exercise,
            performedAt: performedAt,
            weight: weight,
            weightUnit: weightUnit,
            reps: reps,
            durationSeconds: durationSeconds,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        context.insert(restored)
    }
}
