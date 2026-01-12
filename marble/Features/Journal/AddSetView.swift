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

    init(initialPerformedAt: Date = Date()) {
        _performedAt = State(initialValue: initialPerformedAt)
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
                }

                if let exercise = selectedExercise {
                    Section("Metrics") {
                        if exercise.metrics.usesWeight {
                            if exercise.metrics.weight == .optional {
                                Toggle("Added load", isOn: $addedLoad)
                            }

                            if exercise.metrics.weightIsRequired || addedLoad {
                                HStack {
                                    OptionalNumberField(title: "Weight", formatter: Formatters.weight, value: $weight)
                                    Picker("Unit", selection: $weightUnit) {
                                        ForEach(WeightUnit.allCases) { unit in
                                            Text(unit.symbol).tag(unit)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }

                        if exercise.metrics.usesReps {
                            OptionalIntegerField(title: "Reps", value: $reps)
                        }

                        if exercise.metrics.usesDuration {
                            HStack {
                                Text("Duration")
                                Spacer()
                                DurationPicker(durationSeconds: $durationSeconds)
                            }
                        }
                    }

                    Section {
                        RPEPicker(value: $difficulty)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    }

                    Section {
                        RestPicker(restSeconds: $restAfterSeconds)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    }

                    Section {
                        DatePicker("Performed", selection: $performedAt)
                        Button("Now") {
                            performedAt = Date()
                        }
                    }

                    Section {
                        if showNotes || !notes.isEmpty {
                            TextField("Notes", text: $notes, axis: .vertical)
                        } else {
                            Button("Add note") {
                                showNotes = true
                            }
                        }
                    }
                }

                Section {
                    Button("Save") {
                        save(keepOpen: false, startRest: false)
                    }
                    .disabled(!canSave)

                    Button("Save & Add Another") {
                        save(keepOpen: true, startRest: false)
                    }
                    .disabled(!canSave)

                    if restAfterSeconds > 0 {
                        Button("Save & Start Rest") {
                            save(keepOpen: false, startRest: true)
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .onChange(of: selectedExercise) { _, newValue in
                guard let exercise = newValue else { return }
                applyDefaults(for: exercise)
            }
            .task {
                if !didLoadDefaults {
                    loadInitialExercise()
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
            performedAt = DateHelper.merge(day: performedAt, time: Date())
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
            createdAt: Date(),
            updatedAt: Date()
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
            performedAt = Date()
            applyDefaults(for: exercise)
            notes = ""
            showNotes = false
        } else {
            dismiss()
        }
    }
}
