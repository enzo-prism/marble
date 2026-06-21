import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.marbleActiveDay) private var activeDay
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var toast: ToastData?
    @State private var pendingUndo: SetEntrySnapshot?
    @State private var quickLogUndoID: UUID?
    @State private var navPath: [UUID] = []
    @State private var showingImport = false

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
                        .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                        .accessibilityIdentifier("Journal.EmptyState.LogSet")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                    .accessibilityIdentifier("Journal.EmptyState")
                }
                ForEach(daySections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            JournalRow(
                                entry: entry,
                                onDuplicate: { duplicate(entry) },
                                onDelete: { delete(entry) }
                            )
                        }
                    } header: {
                        SectionHeaderView(title: DateHelper.dayLabel(for: section.day, now: activeDay))
                    }
                    .textCase(nil)
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .contentMargins(.top, MarbleSpacing.xs, for: .scrollContent)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Journal.List")
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Workouts")
                    .accessibilityIdentifier("Journal.ImportWorkouts")

                    NavigationLink {
                        NotificationsView(scheduler: CustomNotificationScheduler.live())
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Notifications")
                    .accessibilityIdentifier("Journal.Notifications")

                    AddSetToolbarButton()
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportView.default()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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
            .overlay(alignment: .topLeading) {
                if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit, let latest = entries.first {
                    Button {
                        navPath.append(latest.id)
                    } label: {
                        Color.white.opacity(0.001)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Open Latest")
                    .accessibilityIdentifier("Journal.TestOpenLatest")
                }
            }
        }
    }

    private var daySections: [JournalDaySection] {
        // entries arrive sorted newest-first from the query, so grouping
        // preserves the in-day order without a per-day re-sort.
        let grouped = Dictionary(grouping: entries) { entry in
            DateHelper.startOfDay(for: entry.performedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            JournalDaySection(day: day, entries: grouped[day] ?? [])
        }
    }

    private func delete(_ entry: SetEntry) {
        let snapshot = SetEntrySnapshot(entry: entry)
        modelContext.delete(entry)
        guard modelContext.saveOrRollback() else {
            toast = ToastData(message: "Couldn't delete set", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.warning()
        pendingUndo = snapshot
        quickLogUndoID = nil
        toast = ToastData(message: "Set deleted", actionTitle: "Undo") {
            undoDelete()
        }
    }

    private func undoDelete() {
        guard let snapshot = pendingUndo else { return }
        snapshot.restore(in: modelContext)
        guard modelContext.saveOrRollback() else {
            toast = ToastData(message: "Couldn't restore set", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.lightImpact()
        pendingUndo = nil
        toast = nil
    }

    private func quickLogAgain() {
        guard let latest = entries.first else { return }
        let duplicate = latest.duplicated(at: AppEnvironment.now)
        modelContext.insert(duplicate)
        guard modelContext.saveOrRollback() else {
            toast = ToastData(message: "Couldn't log set", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.success()
        RestActivityController.shared.startRest(for: duplicate)
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
            if modelContext.saveOrRollback() {
                MarbleHaptics.lightImpact()
            }
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
        let duplicate = entry.duplicated(at: AppEnvironment.now)
        modelContext.insert(duplicate)
        if modelContext.saveOrRollback() {
            MarbleHaptics.success()
            RestActivityController.shared.startRest(for: duplicate)
        } else {
            toast = ToastData(message: "Couldn't duplicate set", actionTitle: nil, onAction: nil)
        }
    }
}

private struct JournalDaySection: Identifiable {
    let day: Date
    let entries: [SetEntry]

    var id: Date { day }
}

private struct JournalRow: View {
    let entry: SetEntry
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationLink(value: entry.id) {
            SetRowView(
                entry: entry,
                accessibilityIdentifier: "SetRow.\(entry.id.uuidString)"
            )
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
            .accessibilityLabel(SetRowView.accessibilitySummary(for: entry))
            .accessibilityHint("Open set details")
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
                .tint(Theme.destructiveActionColor(for: colorScheme))
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
    let distance: Double?
    let distanceUnit: DistanceUnit
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
        distance = entry.distance
        distanceUnit = entry.distanceUnit
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
            distance: distance,
            distanceUnit: distanceUnit,
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
