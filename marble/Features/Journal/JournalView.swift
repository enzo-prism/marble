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

    @Query(sort: \SprintRepDetail.createdAt)
    private var sprintRepDetails: [SprintRepDetail]

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
                    LogModePicker()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                }

                Section {
                    QuickLogCardView(
                        entry: entries.first,
                        prBadge: entries.first.flatMap { derived.prBadges[$0.id] } ?? [],
                        sprintGoal: entries.first.flatMap { derived.sprintGoals[$0.id] },
                        sprintDetail: entries.first.flatMap { derived.sprintDetails[$0.id] },
                        bestCue: derived.quickLogBestCue,
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
                                sprintDetail: derived.sprintDetails[entry.id],
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
            .navigationTitle("Log")
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

                LogSetToolbarItems()
            }
            .sheet(isPresented: $showingImport) {
                ImportView.default()
                    .navigationTransition(.zoom(sourceID: "journal-import", in: importZoomNamespace))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onReceive(NotificationCenter.default.publisher(for: .marbleOpenTextImport)) { _ in
                showingImport = true
            }
            .onAppear {
                if PendingTextImport.hasPending {
                    showingImport = true
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
        let latestEntry = entries.first
        let signature = JournalSectionsSignature(
            count: entries.count,
            latestUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast,
            sprintGoalCount: sprintGoalSnapshots.count,
            sprintDetailCount: sprintRepDetails.count,
            latestEntryID: latestEntry?.id,
            latestExerciseID: latestEntry?.exercise.id,
            latestExerciseMetrics: latestEntry?.exercise.metrics,
            latestResistanceTrackingStyle: latestEntry?.exercise.resistanceTrackingStyle
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
            let sprintGoals = Dictionary(
                sprintGoalSnapshots.map { ($0.setEntryID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let sprintDetails = Dictionary(
                sprintRepDetails.map { ($0.setEntryID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            // Precise tenths where a detail exists, rounded legacy seconds
            // otherwise — the sprint-PR trail compares them in one domain.
            let sprintTimes = PersonalRecords.sprintTimes(
                entries: entries,
                sprintGoals: sprintGoals,
                sprintDetails: sprintDetails
            )
            let prBadges = PersonalRecords.badges(for: entries, sprintTimes: sprintTimes)
            let quickLogBestCue = latestEntry.flatMap {
                QuickLogBestCueResolver.resolve(latest: $0, entries: entries)
            }
            return JournalDerived(
                sections: sections,
                prBadges: prBadges,
                sprintGoals: sprintGoals,
                sprintDetails: sprintDetails,
                quickLogBestCue: quickLogBestCue
            )
        }
    }

    private func delete(_ entry: SetEntry) {
        let sprintGoal = sprintGoalSnapshots.first { $0.setEntryID == entry.id }
        let sprintDetail = sprintRepDetails.first { $0.setEntryID == entry.id }
        // `WorkoutSession.entries` has no inverse, so membership can only be
        // recovered by asking the sessions — capture it while the entry lives.
        let entryID = entry.id
        let owningSessions = ((try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .filter { session in session.entries.contains { $0.id == entryID } }
        let snapshot = SetEntrySnapshot(entry: entry, sprintGoal: sprintGoal, sprintDetail: sprintDetail, owningSessions: owningSessions)
        if let sprintGoal { modelContext.delete(sprintGoal) }
        if let sprintDetail { modelContext.delete(sprintDetail) }
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
        guard let duplicate = SetLogging.repeatLatest(of: latest, into: nil, in: modelContext) else {
            toast = ToastData(message: "Couldn't log set", actionTitle: nil, onAction: nil)
            return
        }
        MarbleHaptics.success()
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
            deleteSprintDetail(for: entry.id)
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
        if SetLogging.repeatLatest(of: entry, into: nil, in: modelContext) != nil {
            MarbleHaptics.success()
        } else {
            toast = ToastData(message: "Couldn't duplicate set", actionTitle: nil, onAction: nil)
        }
    }

    private func deleteSprintDetail(for entryID: UUID) {
        let descriptor = FetchDescriptor<SprintRepDetail>(
            predicate: #Predicate { $0.setEntryID == entryID }
        )
        if let detail = try? modelContext.fetch(descriptor).first {
            modelContext.delete(detail)
        }
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
    let sprintDetails: [UUID: SprintRepDetail]
    let quickLogBestCue: QuickLogBestCue?
}

/// Cheap `Equatable` fingerprint for memoizing `daySections`: counts catch
/// inserts/deletes, the latest `updatedAt` catches in-place edits.
private struct JournalSectionsSignature: Equatable {
    let count: Int
    let latestUpdate: Date
    let sprintGoalCount: Int
    let sprintDetailCount: Int
    let latestEntryID: UUID?
    let latestExerciseID: UUID?
    let latestExerciseMetrics: ExerciseMetricsProfile?
    let latestResistanceTrackingStyle: ResistanceTrackingStyle?
}

private struct JournalRow: View {
    let entry: SetEntry
    let prBadge: PersonalRecordBadge
    let sprintGoal: SprintGoalSnapshot?
    let sprintDetail: SprintRepDetail?
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationLink(value: entry.id) {
            SetRowView(
                entry: entry,
                prBadge: prBadge,
                sprintGoal: sprintGoal,
                sprintDetail: sprintDetail,
                accessibilityIdentifier: "SetRow.\(entry.id.uuidString)"
            )
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("SetRow.\(entry.id.uuidString)")
            .accessibilityLabel(SetRowView.accessibilitySummary(for: entry, prBadge: prBadge, sprintGoal: sprintGoal, sprintDetail: sprintDetail))
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
                Text("Private by default. Stored on this device.")
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
    let sprintDetail: SprintRepDetailValue?
    /// Live references survive the entry's deletion (only the entry row dies);
    /// without them, Undo would resurrect the set stripped of its "Imported
    /// from …" lineage and dropped from the workout session that grouped it.
    let importedWorkout: ImportedWorkout?
    let owningSessions: [WorkoutSession]

    init(entry: SetEntry, sprintGoal: SprintGoalSnapshot?, sprintDetail: SprintRepDetail?, owningSessions: [WorkoutSession]) {
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
        self.sprintDetail = sprintDetail.map(SprintRepDetailValue.init)
        importedWorkout = entry.importedWorkout
        self.owningSessions = owningSessions
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
        restored.importedWorkout = importedWorkout
        for session in owningSessions {
            session.append(restored, at: session.updatedAt)
        }
        sprintGoal?.restore(for: restored, in: context)
        sprintDetail?.restore(for: restored, in: context)
    }
}

private nonisolated struct SprintRepDetailValue {
    let id: UUID
    let durationTenths: Int
    let targetLowerTenths: Int
    let targetUpperTenths: Int
    let variantID: UUID?
    let createdAt: Date

    init(_ detail: SprintRepDetail) {
        id = detail.id
        durationTenths = detail.durationTenths
        targetLowerTenths = detail.targetLowerTenths
        targetUpperTenths = detail.targetUpperTenths
        variantID = detail.variantID
        createdAt = detail.createdAt
    }

    func restore(for entry: SetEntry, in context: ModelContext) {
        context.insert(SprintRepDetail(
            id: id,
            setEntryID: entry.id,
            durationTenths: durationTenths,
            targetLowerTenths: targetLowerTenths,
            targetUpperTenths: targetUpperTenths,
            variantID: variantID,
            createdAt: createdAt
        ))
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
