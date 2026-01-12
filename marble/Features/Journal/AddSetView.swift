import SwiftUI
import SwiftData

struct AddSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var selectedExercise: Exercise?
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
    @State private var didLoadDefaults = false

    init(initialPerformedAt: Date = AppEnvironment.now, initialExercise: Exercise? = nil) {
        _performedAt = State(initialValue: initialPerformedAt)
        _selectedExercise = State(initialValue: initialExercise)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExercisePickerView(selectedExercise: $selectedExercise)
                    } label: {
                        HStack {
                            Text("Exercise")
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Spacer()
                            Text(selectedExercise?.name ?? "Select")
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                    .accessibilityIdentifier("AddSet.ExercisePicker")
                }

                if let exercise = selectedExercise {
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
                                .accessibilityIdentifier("AddSet.Notes")
                        } else {
                            Button("Add note") {
                                showNotes = true
                            }
                            .accessibilityIdentifier("AddSet.AddNote")
                        }
                    }
                }

                Section {
                    Button("Save") {
                        save(keepOpen: false, startRest: false)
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("AddSet.Save")

                    Button("Save & Add Another") {
                        save(keepOpen: true, startRest: false)
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("AddSet.SaveAddAnother")

                    if restAfterSeconds > 0 {
                        Button("Save & Start Rest") {
                            save(keepOpen: false, startRest: true)
                        }
                        .disabled(!canSave)
                        .accessibilityIdentifier("AddSet.SaveStartRest")
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("AddSet.List")
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .onChange(of: selectedExercise) { _, newValue in
                guard let exercise = newValue else { return }
                applyDefaults(for: exercise)
            }
            .task {
                if !didLoadDefaults {
                    if let exercise = selectedExercise {
                        applyDefaults(for: exercise)
                    } else {
                        loadInitialExercise()
                    }
                    didLoadDefaults = true
                }
            }
            .sheet(isPresented: $showRestTimer) {
                RestTimerView(totalSeconds: restAfterSeconds)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .sheetGlassBackground()
            }
        }
    }

    private var canSave: Bool {
        guard let exercise = selectedExercise else { return false }
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

    private func loadInitialExercise() {
        if let recent = entries.first {
            selectedExercise = recent.exercise
            performedAt = DateHelper.merge(day: performedAt, time: AppEnvironment.now)
            return
        }

        if let favorite = exercises.first(where: { $0.isFavorite }) {
            selectedExercise = favorite
        } else if let first = exercises.first {
            selectedExercise = first
        }
    }

    private func applyDefaults(for exercise: Exercise) {
        if let last = entries.first(where: { $0.exercise.id == exercise.id }) {
            weight = last.weight
            weightUnit = last.weightUnit
            reps = last.reps
            durationSeconds = last.durationSeconds
            difficulty = last.difficulty
            restAfterSeconds = last.restAfterSeconds
            addedLoad = last.weight != nil
        } else {
            weight = nil
            reps = nil
            durationSeconds = exercise.metrics.usesDuration ? 60 : nil
            difficulty = 8
            restAfterSeconds = exercise.defaultRestSeconds
            addedLoad = false
        }
    }

    private func save(keepOpen: Bool, startRest: Bool) {
        guard let exercise = selectedExercise else { return }

        let resolvedWeight: Double? = {
            if exercise.metrics.weight == .optional, !addedLoad {
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
            reps: exercise.metrics.usesReps ? reps : nil,
            durationSeconds: exercise.metrics.usesDuration ? durationSeconds : nil,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: notes.isEmpty ? nil : notes,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(entry)

        if startRest {
            showRestTimer = true
            if !keepOpen {
                dismiss()
            }
            return
        }

        if keepOpen {
            performedAt = AppEnvironment.now
            applyDefaults(for: exercise)
            notes = ""
            showNotes = false
        } else {
            dismiss()
        }
    }
}
