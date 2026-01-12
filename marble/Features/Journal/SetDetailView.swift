import SwiftUI
import SwiftData

struct SetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var entry: SetEntry

    @State private var addedLoad = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExercisePickerView(selectedExercise: exerciseBinding)
                } label: {
                    HStack {
                        Text("Exercise")
                        Spacer()
                        Text(entry.exercise.name)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
            }

            Section("Metrics") {
                if entry.exercise.metrics.usesWeight {
                    if entry.exercise.metrics.weight == .optional {
                        Toggle("Added load", isOn: $addedLoad)
                            .onChange(of: addedLoad) { _, newValue in
                                if !newValue {
                                    entry.weight = nil
                                }
                            }
                    }

                    if entry.exercise.metrics.weightIsRequired || addedLoad {
                        HStack {
                            OptionalNumberField(title: "Weight", formatter: Formatters.weight, value: weightBinding)
                            Picker("Unit", selection: $entry.weightUnit) {
                                ForEach(WeightUnit.allCases) { unit in
                                    Text(unit.symbol).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                if entry.exercise.metrics.usesReps {
                    OptionalIntegerField(title: "Reps", value: repsBinding)
                }

                if entry.exercise.metrics.usesDuration {
                    HStack {
                        Text("Duration")
                        Spacer()
                        DurationPicker(durationSeconds: durationBinding)
                    }
                }
            }

            Section {
                RPEPicker(value: $entry.difficulty)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
            }

            Section {
                RestPicker(restSeconds: $entry.restAfterSeconds)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
            }

            Section {
                DatePicker("Performed", selection: $entry.performedAt)
            }

            Section {
                TextField("Notes", text: notesBinding, axis: .vertical)
            }

            Section {
                Button("Duplicate") {
                    duplicate()
                }

                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                    dismiss()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle("Set Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .onAppear {
            if entry.exercise.metrics.weight == .optional {
                addedLoad = entry.weight != nil
            }
        }
        .onChange(of: entry.exercise) { _, newValue in
            if newValue.metrics.weight == .optional {
                addedLoad = entry.weight != nil
            } else {
                addedLoad = true
            }
        }
        .onDisappear {
            entry.updatedAt = Date()
        }
    }

    private var exerciseBinding: Binding<Exercise?> {
        Binding(
            get: { entry.exercise },
            set: { newValue in
                if let newValue {
                    entry.exercise = newValue
                }
            }
        )
    }

    private var weightBinding: Binding<Double?> {
        Binding(
            get: { entry.weight },
            set: { entry.weight = $0 }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { entry.reps },
            set: { entry.reps = $0 }
        )
    }

    private var durationBinding: Binding<Int?> {
        Binding(
            get: { entry.durationSeconds },
            set: { entry.durationSeconds = $0 }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { entry.notes ?? "" },
            set: { entry.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private func duplicate() {
        let duplicate = SetEntry(
            exercise: entry.exercise,
            performedAt: Date(),
            weight: entry.weight,
            weightUnit: entry.weightUnit,
            reps: entry.reps,
            durationSeconds: entry.durationSeconds,
            difficulty: entry.difficulty,
            restAfterSeconds: entry.restAfterSeconds,
            notes: entry.notes,
            createdAt: Date(),
            updatedAt: Date()
        )
        modelContext.insert(duplicate)
    }
}
