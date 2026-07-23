import SwiftData
import SwiftUI

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(QuickLogCoordinator.self) private var quickLog

    @Query(WorkoutSessionQueries.active)
    private var activeSessions: [WorkoutSession]

    @Query(WorkoutSessionQueries.recentCompleted)
    private var recentSessions: [WorkoutSession]

    @Query(filter: #Predicate<SplitPlan> { $0.isActive == true }, sort: \SplitPlan.updatedAt, order: .reverse)
    private var plans: [SplitPlan]

    @Query(sort: \SprintPrescription.createdAt)
    private var sprintPrescriptions: [SprintPrescription]

    @State private var showingPlan = false
    @State private var showingSettings = false
    @State private var showingFinishConfirmation = false
    @State private var errorMessage: String?

    private var activeSession: WorkoutSession? {
        activeSessions.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                List {
                if let activeSession {
                    ActiveWorkoutSection(
                        session: activeSession,
                        onAddSet: openAddSet,
                        onRepeatSet: repeatSet,
                        onFinish: { showingFinishConfirmation = true }
                    )
                } else {
                    StartWorkoutSection(
                        title: suggestedTitle,
                        plannedSets: todayPlannedSets,
                        sprintPrescriptions: sprintPrescriptions,
                        onStart: { _ = startWorkout() },
                        onStartAndLog: startAndLog,
                        onEditPlan: { showingPlan = true }
                    )
                }

                if !recentSessions.isEmpty {
                    Section {
                        ForEach(recentSessions) { session in
                            WorkoutSessionRow(session: session)
                        }
                    } header: {
                        SectionHeaderView(title: "Recent Workouts")
                    }
                }
            }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("Workout.List")
                .navigationTitle("Workout")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingPlan = true
                        } label: {
                            Image(systemName: "list.bullet.clipboard")
                        }
                        .accessibilityLabel("Workout plan")
                        .accessibilityIdentifier("Workout.Plan")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        // Identifier intentionally unchanged: WorkoutFlowUITests
                        // and AppStoreScreenshotUITests both drive this button by
                        // "Workout.Data". Only the destination moved — Data &
                        // Backups now lives one level in, under Settings.
                        .accessibilityIdentifier("Workout.Data")
                    }

                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        AddSetToolbarButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlan) {
            SplitView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .confirmationDialog("Finish this workout?", isPresented: $showingFinishConfirmation) {
            Button("Finish Workout") { finishWorkout() }
                .accessibilityIdentifier("Workout.Finish.Confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("Workout.Finish.Cancel")
        } message: {
            Text("Your sets stay in the Journal and this session becomes part of your workout history.")
        }
        .alert("Workout Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("Workout.Error.OK")
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
    }

    private var activePlan: SplitPlan? { plans.first }

    private var todayPlannedSets: [PlannedSet] {
        guard let day = todaySplitDay else { return [] }
        return day.plannedSets.sorted { $0.order < $1.order }
    }

    private var todaySplitDay: SplitDay? {
        guard let plan = activePlan else { return nil }
        let calendarWeekday = Calendar.current.component(.weekday, from: AppEnvironment.now)
        let weekday = Weekday.allCases.first { $0.calendarWeekday == calendarWeekday }
        return plan.days.first { $0.weekday == weekday }
    }

    private var suggestedTitle: String {
        let title = todaySplitDay?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Today's Workout" : title
    }

    @discardableResult
    private func startWorkout() -> WorkoutSession? {
        let now = AppEnvironment.now
        let session = WorkoutSession(title: suggestedTitle, startedAt: now, createdAt: now, updatedAt: now)
        modelContext.insert(session)
        guard modelContext.saveOrRollback() else {
            errorMessage = "Marble couldn't start the workout."
            return nil
        }
        MarbleHaptics.success()
        return session
    }

    private func startAndLog(_ plannedSet: PlannedSet) {
        guard let session = startWorkout() else { return }
        quickLog.open(
            prefillExerciseID: plannedSet.exercise.id,
            workoutSessionID: session.id,
            context: QuickLogContext(title: "Workout", source: suggestedTitle)
        )
    }

    private func openAddSet() {
        quickLog.open(
            workoutSessionID: activeSession?.id,
            context: QuickLogContext(title: "Workout", source: activeSession?.title ?? suggestedTitle)
        )
    }

    private func repeatSet(_ entry: SetEntry) {
        quickLog.open(
            prefillExerciseID: entry.exercise.id,
            workoutSessionID: activeSession?.id,
            context: QuickLogContext(title: "Workout", source: activeSession?.title ?? suggestedTitle)
        )
    }

    private func finishWorkout() {
        guard let activeSession else { return }
        activeSession.finish()
        guard modelContext.saveOrRollback() else {
            errorMessage = "Marble couldn't finish the workout."
            return
        }
        RestActivityController.shared.cancelRest()
        MarbleHaptics.success()
    }
}

private struct ActiveWorkoutSection: View {
    let session: WorkoutSession
    let onAddSet: () -> Void
    let onRepeatSet: (SetEntry) -> Void
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Text(session.title)
                            .font(MarbleTypography.rowTitle)
                        if TestHooks.isAppStoreScreenshotting {
                            Text("48:12")
                                .font(MarbleTypography.rowSubtitle.monospacedDigit())
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        } else {
                            Text(session.startedAt, style: .timer)
                                .font(MarbleTypography.rowSubtitle.monospacedDigit())
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                    Spacer()
                    Text("LIVE")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.backgroundColor(for: colorScheme))
                        .padding(.horizontal, MarbleSpacing.s)
                        .padding(.vertical, MarbleSpacing.xxs)
                        .background(Capsule().fill(Theme.primaryTextColor(for: colorScheme)))
                }

                HStack(spacing: MarbleSpacing.xs) {
                    Button("Add Set", systemImage: "plus", action: onAddSet)
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                        .accessibilityIdentifier("Workout.AddSet")
                    Button("Finish", systemImage: "checkmark", action: onFinish)
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                        .accessibilityIdentifier("Workout.Finish")
                }
            }
            .padding(MarbleSpacing.m)
            .marbleCardBackground()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .marbleRowInsets()

            if session.orderedEntries.isEmpty {
                EmptyStateView(title: "No sets yet", message: "Add your first set to begin the workout.", systemImage: "plus.circle")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
            } else {
                ForEach(session.orderedEntries) { entry in
                    Button { onRepeatSet(entry) } label: {
                        SetRowView(entry: entry, accessibilityIdentifier: "Workout.Set.\(entry.id.uuidString)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Log another set for this exercise")
                }
            }
        } header: {
            SectionHeaderView(title: "Active Workout")
        }
    }
}

private struct StartWorkoutSection: View {
    let title: String
    let plannedSets: [PlannedSet]
    let sprintPrescriptions: [SprintPrescription]
    let onStart: () -> Void
    let onStartAndLog: (PlannedSet) -> Void
    let onEditPlan: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                Text(title)
                    .font(MarbleTypography.rowTitle)
                Text(plannedSets.isEmpty ? "Start freely, or add exercises to today's split." : "\(plannedSets.count) planned sets ready.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStart) {
                    Label {
                        Text("Start Workout")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                    .accessibilityIdentifier("Workout.Start")
            }
            .padding(MarbleSpacing.m)
            .marbleCardBackground()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .marbleRowInsets()

            ForEach(plannedSets) { plannedSet in
                Button { onStartAndLog(plannedSet) } label: {
                    HStack {
                        ExerciseIconView(exercise: plannedSet.exercise, fontSize: 17, frameSize: 28)
                        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                            Text(plannedSet.exercise.name)
                                .font(MarbleTypography.rowTitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            if let prescription = sprintPrescriptions.first(where: { $0.exerciseID == plannedSet.exercise.id }) {
                                Text(prescription.summary(
                                    distanceUnit: plannedSet.exercise.preferredDistanceUnit,
                                    restSeconds: plannedSet.exercise.defaultRestSeconds
                                ))
                                .font(MarbleTypography.rowMeta)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Workout.PlannedSet.\(plannedSet.id.uuidString)")
            }

            Button(action: onEditPlan) {
                Label {
                    Text("Edit Workout Plan")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .padding(.vertical, MarbleSpacing.xxs)
            }
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("Workout.EditPlan")
        } header: {
            SectionHeaderView(title: "Today")
        }
    }
}

private struct WorkoutSessionRow: View {
    let session: WorkoutSession

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(session.title)
                    .font(MarbleTypography.rowTitle)
                Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: MarbleSpacing.xxxs) {
                Text("\(session.entries.count) sets")
                    .font(MarbleTypography.rowSubtitle)
                Text(DateHelper.formattedDuration(seconds: Int(session.duration)))
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Workout.Recent.\(session.id.uuidString)")
    }
}
