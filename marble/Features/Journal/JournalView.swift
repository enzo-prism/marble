import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var toast: ToastData?
    @State private var pendingUndo: SetEntrySnapshot?
    @State private var quickLogUndoID: UUID?
    @State private var navPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    QuickLogCardView(
                        entry: entries.first,
                        onLogAgain: { quickLogAgain() },
                        onEdit: { openEdit() },
                        onLogSet: { quickLog.open() }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    VStack(spacing: MarbleSpacing.m) {
                        EmptyStateView(title: "No sets yet", message: "Log your first set to start building momentum.", systemImage: "list.bullet.rectangle")
                        Button("Log Set") {
                            quickLog.open()
                        }
                        .buttonStyle(MarbleActionButtonStyle())
                        .accessibilityIdentifier("Journal.EmptyState.LogSet")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                    .accessibilityIdentifier("Journal.EmptyState")
                }
                ForEach(sectionedDays, id: \.self) { day in
                    if let dayEntries = groupedEntries[day] {
                        Section {
                            ForEach(dayEntries) { entry in
                                JournalRow(
                                    entry: entry,
                                    onSelect: { navPath.append(entry.id) },
                                    onDuplicate: { duplicate(entry) },
                                    onDelete: { delete(entry) }
                                )
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
                if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit, let latest = entries.first {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Open Latest") {
                            navPath.append(latest.id)
                        }
                        .accessibilityIdentifier("Journal.TestOpenLatest")
                        .opacity(0.01)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { entryID in
                if let entry = entries.first(where: { $0.id == entryID }) {
                    SetDetailView(entry: entry)
                } else {
                    Text("Set not found")
                        .font(MarbleTypography.body)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
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
        try? modelContext.save()
        pendingUndo = snapshot
        quickLogUndoID = nil
        toast = ToastData(message: "Set deleted", actionTitle: "Undo") {
            undoDelete()
        }
    }

    private func undoDelete() {
        guard let snapshot = pendingUndo else { return }
        snapshot.restore(in: modelContext)
        try? modelContext.save()
        pendingUndo = nil
        toast = nil
    }

    private func quickLogAgain() {
        guard let latest = entries.first else { return }
        let now = AppEnvironment.now
        let duplicate = SetEntry(
            exercise: latest.exercise,
            performedAt: now,
            weight: latest.weight,
            weightUnit: latest.weightUnit,
            reps: latest.reps,
            durationSeconds: latest.durationSeconds,
            difficulty: latest.difficulty,
            restAfterSeconds: latest.restAfterSeconds,
            notes: latest.notes,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(duplicate)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return
        }
        pendingUndo = nil
        quickLogUndoID = duplicate.id
        toast = ToastData(message: "Set logged again", actionTitle: "Undo") {
            undoQuickLog()
        }
    }

    private func undoQuickLog() {
        guard let id = quickLogUndoID else { return }
        let descriptor = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == id })
        if let entry = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        quickLogUndoID = nil
        toast = nil
    }

    private func openEdit() {
        guard let latest = entries.first else {
            quickLog.open()
            return
        }
        quickLog.open(prefillExerciseID: latest.exercise.id)
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
        try? modelContext.save()
    }
}

private struct JournalRow: View {
    let entry: SetEntry
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SetRowView(entry: entry)
            .foregroundColor(Theme.primaryTextColor(for: colorScheme))
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SetRowView.accessibilitySummary(for: entry))
            .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onSelect()
            }
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .marbleRowInsets()
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(Theme.dividerColor(for: colorScheme))
                .accessibilityIdentifier("SetRow.\(entry.id.uuidString).Duplicate")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("SetRow.\(entry.id.uuidString).Delete")
            }
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
