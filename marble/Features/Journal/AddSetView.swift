import SwiftUI
import SwiftData
import UIKit

struct AddSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Binding private var isPresented: Bool
    @State private var selectedExerciseID: UUID?
    @State private var selectedExerciseSnapshot: ExerciseSnapshot?
    @State private var performedAt: Date
    @State private var weight: Double?
    @State private var weightUnit: WeightUnit = .lb
    @State private var reps: Int?
    @State private var durationSeconds: Int?
    @State private var difficulty: Int = 8
    @State private var restAfterSeconds: Int = 60
    @State private var notes: String = ""
    @State private var showNotes = false
    @State private var addedLoad = false
    @State private var showRestTimer = false
    @State private var didInitialize = false
    @State private var showSaveError = false
    @State private var showMissingExercise = false

    init(initialPerformedAt: Date = AppEnvironment.now, initialExercise: Exercise? = nil, isPresented: Binding<Bool> = .constant(true)) {
        _performedAt = State(initialValue: initialPerformedAt)
        _selectedExerciseID = State(initialValue: initialExercise?.id)
        _isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        NavigationLink {
                            ExercisePickerView(selectedExercise: exerciseSelection)
                    } label: {
                        HStack {
                            Text("Exercise")
                                .font(MarbleTypography.rowTitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Spacer()
                            Text(selectedExerciseSnapshot?.name ?? "Select")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                    .accessibilityIdentifier("AddSet.ExercisePicker")
                }

                if let exercise = selectedExerciseSnapshot {
                    Section {
                        if exercise.metrics.usesWeight {
                            if exercise.metrics.weight == .optional {
                                Toggle("Added load", isOn: $addedLoad)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .accessibilityIdentifier("AddSet.AddedLoad")
                            }

                            if exercise.metrics.weightIsRequired || addedLoad {
                                HStack {
                                    OptionalNumberField(title: "Weight", formatter: Formatters.weight, value: $weight, accessibilityIdentifier: "AddSet.Weight")
                                    Picker("Unit", selection: $weightUnit) {
                                        ForEach(WeightUnit.allCases) { unit in
                                            Text(unit.symbol).tag(unit)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .accessibilityIdentifier("AddSet.WeightUnit")
                                }
                            }
                        }

                        if exercise.metrics.usesReps {
                            OptionalIntegerField(title: "Reps", value: $reps, accessibilityIdentifier: "AddSet.Reps")
                        }

                        if exercise.metrics.usesDuration {
                            HStack {
                                Text("Duration")
                                    .font(MarbleTypography.rowTitle)
                                Spacer()
                                DurationPicker(durationSeconds: $durationSeconds)
                                    .accessibilityIdentifier("AddSet.Duration")
                            }
                        }
                    } header: {
                        SectionHeaderView(title: "Metrics")
                    }

                    Section {
                        RPEPicker(value: $difficulty)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.RPE")
                    }

                    Section {
                        RestPicker(restSeconds: $restAfterSeconds)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.RestPicker")
                    }

                    Section {
                        DatePicker("Performed", selection: $performedAt)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.PerformedAt")
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        HStack {
                            Text("Now")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            performedAt = AppEnvironment.now
                        }
                        .accessibilityIdentifier("AddSet.Now")
                        .accessibilityLabel("Now")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            performedAt = AppEnvironment.now
                        }
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    }

                    Section {
                        if showNotes || !notes.isEmpty {
                            TextField("Notes", text: $notes, axis: .vertical)
                                .marbleFieldStyle()
                                .accessibilityIdentifier("AddSet.Notes")
                        } else {
                            Button("Add note") {
                                showNotes = true
                            }
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.AddNote")
                        }
                    }
                }

                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("AddSet.List")
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .safeAreaInset(edge: .bottom) {
                saveButtons
            }
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .onChange(of: selectedExerciseID) { _, newValue in
                guard let newValue else {
                    selectedExerciseSnapshot = nil
                    return
                }
                hydrateSelection(id: newValue, shouldApplyDefaults: true)
            }
            .onAppear {
                validateSelection()
                guard !didInitialize else { return }
                if let selectedExerciseID {
                    hydrateSelection(id: selectedExerciseID, shouldApplyDefaults: true)
                } else {
                    loadInitialExercise()
                }
                didInitialize = true
            }
            .sheet(isPresented: $showRestTimer) {
                RestTimerView(totalSeconds: restAfterSeconds)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .sheetGlassBackground()
            }
            .alert("Unable to Save", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't save this set. Please try again.")
            }
            .alert("Exercise Removed", isPresented: $showMissingExercise) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That exercise was removed. Choose another one before saving.")
            }
        }
    }

    private var exerciseSelection: Binding<Exercise?> {
        Binding(
            get: { nil },
            set: { newValue in
                guard let newValue else {
                    selectedExerciseID = nil
                    selectedExerciseSnapshot = nil
                    return
                }
                selectExercise(newValue, lastEntry: fetchLastEntry(for: newValue.id))
            }
        )
    }

    private var canSave: Bool {
        guard let exercise = selectedExerciseSnapshot else { return false }
        if exercise.metrics.weightIsRequired, weight == nil {
            return false
        }
        if exercise.metrics.repsIsRequired, reps == nil {
            return false
        }
        if exercise.metrics.durationIsRequired, (durationSeconds ?? 0) == 0 {
            return false
        }
        return true
    }

    private var effectiveCanSave: Bool {
        guard selectedExerciseSnapshot != nil else { return false }
        return canSave || TestHooks.isUITesting
    }

    private var saveButtons: some View {
        VStack(spacing: MarbleSpacing.s) {
            Button("Save") {
                save(keepOpen: false, startRest: false)
            }
            .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
            .allowsHitTesting(effectiveCanSave)
            .accessibilityIdentifier("AddSet.Save")

            Button("Save & Add Another") {
                save(keepOpen: true, startRest: false)
            }
            .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
            .allowsHitTesting(effectiveCanSave)
            .accessibilityIdentifier("AddSet.SaveAddAnother")

            if restAfterSeconds > 0, canSave {
                Button("Save & Start Rest") {
                    save(keepOpen: false, startRest: true)
                }
                .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
                .allowsHitTesting(effectiveCanSave)
                .accessibilityIdentifier("AddSet.SaveStartRest")
            }
        }
        .padding(.horizontal, MarbleLayout.pagePadding)
        .padding(.top, MarbleSpacing.s)
        .padding(.bottom, MarbleSpacing.m)
        .background(Theme.backgroundColor(for: colorScheme))
        .overlay(alignment: .top) {
            Divider()
                .background(Theme.dividerColor(for: colorScheme))
        }
    }

    private func loadInitialExercise() {
        if let recent = fetchMostRecentEntry() {
            selectExercise(recent.exercise, lastEntry: recent)
            performedAt = DateHelper.merge(day: performedAt, time: AppEnvironment.now)
            return
        }

        if let favorite = fetchFavoriteExercise() {
            selectExercise(favorite, lastEntry: fetchLastEntry(for: favorite.id))
            return
        }

        if let first = fetchFirstExercise() {
            selectExercise(first, lastEntry: fetchLastEntry(for: first.id))
        }
    }

    private func applyDefaults(for exercise: ExerciseSnapshot, lastEntry: SetEntry?) {
        if let lastEntry {
            weight = lastEntry.weight
            weightUnit = lastEntry.weightUnit
            reps = lastEntry.reps
            durationSeconds = lastEntry.durationSeconds
            difficulty = lastEntry.difficulty
            restAfterSeconds = lastEntry.restAfterSeconds
            addedLoad = lastEntry.weight != nil
            return
        }
        weight = nil
        reps = nil
        durationSeconds = exercise.metrics.usesDuration ? 60 : nil
        difficulty = 8
        restAfterSeconds = exercise.defaultRestSeconds
        addedLoad = false
    }

    private func save(keepOpen: Bool, startRest: Bool) {
        dismissKeyboard()
        guard let selectedExerciseID else {
            showMissingExercise = selectedExerciseSnapshot != nil
            return
        }
        guard let exercise = fetchExercise(id: selectedExerciseID) else {
            selectedExerciseSnapshot = nil
            showMissingExercise = true
            return
        }
        guard canSave || TestHooks.isUITesting else { return }

        let metrics = exercise.metrics
        let resolvedWeight: Double? = {
            if metrics.weight == .optional, !addedLoad {
                return nil
            }
            return weight
        }()

        let now = AppEnvironment.now
        let entry = SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: resolvedWeight,
            weightUnit: weightUnit,
            reps: metrics.usesReps ? reps : nil,
            durationSeconds: metrics.usesDuration ? durationSeconds : nil,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: notes.isEmpty ? nil : notes,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(entry)
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Save set failed: \(error)")
            #endif
            modelContext.rollback()
            showSaveError = true
            return
        }

        let snapshot = ExerciseSnapshot(exercise)
        if startRest {
            resetForm(for: snapshot, lastEntry: entry)
            showRestTimer = true
            return
        }

        if keepOpen {
            resetForm(for: snapshot, lastEntry: entry)
        } else {
            closeSheet()
        }
    }

    private func resetForm(for exercise: ExerciseSnapshot, lastEntry: SetEntry?) {
        selectedExerciseID = exercise.id
        selectedExerciseSnapshot = exercise
        performedAt = AppEnvironment.now
        applyDefaults(for: exercise, lastEntry: lastEntry)
        notes = ""
        showNotes = false
    }

    private func closeSheet() {
        quickLog.isPresentingAddSet = false
        isPresented = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension AddSetView {
    struct ExerciseSnapshot: Equatable {
        let id: UUID
        let name: String
        let category: ExerciseCategory
        let metrics: ExerciseMetricsProfile
        let defaultRestSeconds: Int

        init(_ exercise: Exercise) {
            id = exercise.id
            name = exercise.name
            category = exercise.category
            metrics = exercise.metrics
            defaultRestSeconds = exercise.defaultRestSeconds
        }
    }

    func selectExercise(_ exercise: Exercise, lastEntry: SetEntry?) {
        let snapshot = ExerciseSnapshot(exercise)
        selectedExerciseID = snapshot.id
        selectedExerciseSnapshot = snapshot
        applyDefaults(for: snapshot, lastEntry: lastEntry)
    }

    func hydrateSelection(id: UUID, shouldApplyDefaults: Bool) {
        guard let exercise = fetchExercise(id: id) else {
            selectedExerciseID = nil
            selectedExerciseSnapshot = nil
            showMissingExercise = true
            return
        }
        let snapshot = ExerciseSnapshot(exercise)
        selectedExerciseSnapshot = snapshot
        if shouldApplyDefaults {
            applyDefaults(for: snapshot, lastEntry: fetchLastEntry(for: id))
        }
    }

    func validateSelection() {
        guard let id = selectedExerciseID else { return }
        guard let exercise = fetchExercise(id: id) else {
            selectedExerciseID = nil
            selectedExerciseSnapshot = nil
            showMissingExercise = true
            return
        }
        selectedExerciseSnapshot = ExerciseSnapshot(exercise)
    }

    func fetchExercise(id: UUID) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchMostRecentEntry() -> SetEntry? {
        var descriptor = FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchLastEntry(for exerciseID: UUID) -> SetEntry? {
        var descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise.id == exerciseID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchFavoriteExercise() -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchFirstExercise() -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
