import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.marbleActiveDay) private var activeDay
    @Environment(QuickLogCoordinator.self) private var quickLog

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \ImportedWorkout.importedAt, order: .reverse)
    private var importedWorkouts: [ImportedWorkout]

    @Query(sort: \SprintGoalSnapshot.createdAt)
    private var sprintGoalSnapshots: [SprintGoalSnapshot]

    @Query(filter: #Predicate<SplitPlan> { $0.isActive == true }, sort: \SplitPlan.updatedAt, order: .reverse)
    private var activeSplitPlans: [SplitPlan]

    /// One-row freshness probe for the memo signature (see LatestUpdateQueries).
    @Query(LatestUpdateQueries.setEntry)
    private var latestUpdatedEntries: [SetEntry]

    @State private var toast: ToastData?
    @State private var pendingUndo: SetEntrySnapshot?
    @State private var quickLogUndoID: UUID?
    @State private var navPath: [UUID] = []
    @State private var showingImport = false
    @Namespace private var importZoomNamespace

    // Grouping the full history by day AND detecting personal-record sets is
    // memoized together so unrelated state changes (a toast appearing, a sheet
    // opening, navigation) don't re-group every entry or recompute records.
    @State private var derivedMemo = RenderMemo<JournalSectionsSignature, JournalDerived>()

    var body: some View {
        let derived = derived
        return NavigationStack(path: $navPath) {
            List {
                Section {
                    QuickLogCardView(
                        entry: entries.first,
                        prBadge: entries.first.flatMap { derived.prBadges[$0.id] } ?? [],
                        sprintGoal: entries.first.flatMap { derived.sprintGoals[$0.id] },
                        onLogAgain: { quickLogAgain() },
                        onEdit: { openEdit() },
                        onLogSet: { quickLog.open() }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                }

                if entries.isEmpty {
                    StartChecklistCard(
                        hasLoggedSet: !entries.isEmpty,
                        hasImportedWorkout: !importedWorkouts.isEmpty,
                        hasSplit: !activeSplitPlans.isEmpty,
                        onLogSet: { quickLog.open() },
                        onImport: { showingImport = true },
                        onCreateSplit: { createSplit() }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                }
                ForEach(derived.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            JournalRow(
                                entry: entry,
                                prBadge: derived.prBadges[entry.id] ?? [],
                                sprintGoal: derived.sprintGoals[entry.id],
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
                // The zoom source lives on the ToolbarItem (not the button) —
                // the canonical placement for toolbar-to-sheet morphs.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Workouts")
                    .accessibilityIdentifier("Journal.ImportWorkouts")
                }
                .matchedTransitionSource(id: "journal-import", in: importZoomNamespace)

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NotificationsView(scheduler: CustomNotificationScheduler.live())
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Notifications")
                    .accessibilityIdentifier("Journal.Notifications")
                }

                // The primary "+" sits in its own glass capsule, visually apart
                // from the secondary import/notification actions.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportView.default()
                    .navigationTransition(.zoom(sourceID: "journal-import", in: importZoomNamespace))
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
                if TestHooks.isUITesting, !TestHooks.isAccessibilityAudit, !TestHooks.isAppStoreScreenshotting, let latest = entries.first {
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

    private var derived: JournalDerived {
        let signature = JournalSectionsSignature(
            count: entries.count,
            latestUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast,
            sprintGoalCount: sprintGoalSnapshots.count
        )
        return derivedMemo.value(for: signature) {
            // entries arrive sorted newest-first from the query, so grouping
            // preserves the in-day order without a per-day re-sort.
            let grouped = Dictionary(grouping: entries) { entry in
                DateHelper.startOfDay(for: entry.performedAt)
            }
            let sections = grouped.keys.sorted(by: >).map { day in
                JournalDaySection(day: day, entries: grouped[day] ?? [])
            }
            let prBadges = PersonalRecords.badges(for: entries)
            let sprintGoals = Dictionary(
                sprintGoalSnapshots.map { ($0.setEntryID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return JournalDerived(sections: sections, prBadges: prBadges, sprintGoals: sprintGoals)
        }
    }

    private func delete(_ entry: SetEntry) {
        let sprintGoal = sprintGoalSnapshots.first { $0.setEntryID == entry.id }
        let snapshot = SetEntrySnapshot(entry: entry, sprintGoal: sprintGoal)
        if let sprintGoal { modelContext.delete(sprintGoal) }
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
        copySprintGoal(from: latest, to: duplicate)
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
            deleteSprintGoal(for: entry.id)
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

    private func createSplit() {
        SeedData.ensureSplitPlan(in: modelContext)
        if modelContext.saveOrRollback() {
            MarbleHaptics.lightImpact()
        }
    }

    private func duplicate(_ entry: SetEntry) {
        let duplicate = entry.duplicated(at: AppEnvironment.now)
        modelContext.insert(duplicate)
        copySprintGoal(from: entry, to: duplicate)
        if modelContext.saveOrRollback() {
            MarbleHaptics.success()
            RestActivityController.shared.startRest(for: duplicate)
        } else {
            toast = ToastData(message: "Couldn't duplicate set", actionTitle: nil, onAction: nil)
        }
    }

    private func copySprintGoal(from source: SetEntry, to destination: SetEntry) {
        guard let sourceGoal = sprintGoalSnapshots.first(where: { $0.setEntryID == source.id }) else { return }
        modelContext.insert(SprintGoalSnapshot(
            setEntryID: destination.id,
            exerciseID: destination.exercise.id,
            distance: sourceGoal.distance,
            distanceUnit: sourceGoal.distanceUnit,
            repetitionNumber: nil,
            repetitionCount: sourceGoal.repetitionCount,
            targetLowerSeconds: sourceGoal.targetLowerSeconds,
            targetUpperSeconds: sourceGoal.targetUpperSeconds,
            isInferred: sourceGoal.isInferred,
            createdAt: destination.createdAt
        ))
    }

    private func deleteSprintGoal(for entryID: UUID) {
        let descriptor = FetchDescriptor<SprintGoalSnapshot>(
            predicate: #Predicate { $0.setEntryID == entryID }
        )
        if let goal = try? modelContext.fetch(descriptor).first {
            modelContext.delete(goal)
        }
    }
}

private struct JournalDaySection: Identifiable {
    let day: Date
    let entries: [SetEntry]

    var id: Date { day }
}

/// Memoized journal derivations: day-grouped sections plus the map of which
/// sets are personal records, keyed by `SetEntry.id`.
private struct JournalDerived {
    let sections: [JournalDaySection]
    let prBadges: [UUID: PersonalRecordBadge]
    let sprintGoals: [UUID: SprintGoalSnapshot]
}

/// Cheap `Equatable` fingerprint for memoizing `daySections`: counts catch
/// inserts/deletes, the latest `updatedAt` catches in-place edits.
private struct JournalSectionsSignature: Equatable {
    let count: Int
    let latestUpdate: Date
    let sprintGoalCount: Int
}

private struct JournalRow: View {
    let entry: SetEntry
    let prBadge: PersonalRecordBadge
    let sprintGoal: SprintGoalSnapshot?
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationLink(value: entry.id) {
            SetRowView(
                entry: entry,
                prBadge: prBadge,
                sprintGoal: sprintGoal,
                accessibilityIdentifier: "SetRow.\(entry.id.uuidString)"
            )
                .foregroundColor(Theme.primaryTextColor(for: colorScheme))
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
            .accessibilityLabel(SetRowView.accessibilitySummary(for: entry, prBadge: prBadge, sprintGoal: sprintGoal))
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

private struct StartChecklistCard: View {
    let hasLoggedSet: Bool
    let hasImportedWorkout: Bool
    let hasSplit: Bool
    let onLogSet: () -> Void
    let onImport: () -> Void
    let onCreateSplit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Text("Start Marble")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Journal.StartChecklist")
                Text("Private by default. Stored on this iPhone.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                StartChecklistItem(title: "Log a set", isComplete: hasLoggedSet)
                StartChecklistItem(title: "Import workouts", isComplete: hasImportedWorkout)
                StartChecklistItem(title: "Create a split", isComplete: hasSplit)
            }

            actionButtons
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
    }

    @ViewBuilder
    private var actionButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: MarbleSpacing.xs) {
                logButton
                importButton
                splitButton
            }
        } else {
            HStack(spacing: MarbleSpacing.xs) {
                logButton
                importButton
                splitButton
            }
        }
    }

    private var logButton: some View {
        Button(action: onLogSet) {
            Label("Log", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
        .accessibilityIdentifier("Journal.StartChecklist.LogSet")
    }

    private var importButton: some View {
        Button(action: onImport) {
            Label("Import", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
        .accessibilityIdentifier("Journal.StartChecklist.Import")
    }

    private var splitButton: some View {
        Button(action: onCreateSplit) {
            Label("Split", systemImage: "list.bullet.clipboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
        .disabled(hasSplit)
        .accessibilityIdentifier("Journal.StartChecklist.CreateSplit")
    }
}

private struct StartChecklistItem: View {
    let title: String
    let isComplete: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(title)
                .font(MarbleTypography.rowMeta)
        } icon: {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .accessibilityLabel("\(title), \(isComplete ? "complete" : "not complete")")
    }
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
    let sprintGoal: SprintGoalSnapshotValue?

    init(entry: SetEntry, sprintGoal: SprintGoalSnapshot?) {
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
        self.sprintGoal = sprintGoal.map(SprintGoalSnapshotValue.init)
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
        sprintGoal?.restore(for: restored, in: context)
    }
}

private nonisolated struct SprintGoalSnapshotValue {
    let id: UUID
    let exerciseID: UUID
    let distance: Double
    let distanceUnit: DistanceUnit
    let repetitionNumber: Int?
    let repetitionCount: Int
    let targetLowerSeconds: Int
    let targetUpperSeconds: Int
    let isInferred: Bool
    let createdAt: Date

    init(_ snapshot: SprintGoalSnapshot) {
        id = snapshot.id
        exerciseID = snapshot.exerciseID
        distance = snapshot.distance
        distanceUnit = snapshot.distanceUnit
        repetitionNumber = snapshot.repetitionNumber
        repetitionCount = snapshot.repetitionCount
        targetLowerSeconds = snapshot.targetLowerSeconds
        targetUpperSeconds = snapshot.targetUpperSeconds
        isInferred = snapshot.isInferred
        createdAt = snapshot.createdAt
    }

    func restore(for entry: SetEntry, in context: ModelContext) {
        context.insert(SprintGoalSnapshot(
            id: id,
            setEntryID: entry.id,
            exerciseID: exerciseID,
            distance: distance,
            distanceUnit: distanceUnit,
            repetitionNumber: repetitionNumber,
            repetitionCount: repetitionCount,
            targetLowerSeconds: targetLowerSeconds,
            targetUpperSeconds: targetUpperSeconds,
            isInferred: isInferred,
            createdAt: createdAt
        ))
    }
}
