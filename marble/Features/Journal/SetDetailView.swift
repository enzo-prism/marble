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
                            .font(MarbleTypography.rowTitle)
                        Spacer()
                        Text(entry.exercise.name)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
                .accessibilityIdentifier("SetDetail.ExercisePicker")
            }

            Section {
                if entry.exercise.metrics.usesWeight {
                    if entry.exercise.metrics.weight == .optional {
                        Toggle("Added load", isOn: $addedLoad)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .onChange(of: addedLoad) { _, newValue in
                                if !newValue {
                                    entry.weight = nil
                                }
                            }
                            .accessibilityIdentifier("SetDetail.AddedLoad")
                    }

                    if entry.exercise.metrics.weightIsRequired || addedLoad {
                        HStack {
                            OptionalNumberField(title: "Weight", formatter: Formatters.weight, value: weightBinding, accessibilityIdentifier: "SetDetail.Weight")
                            Picker("Unit", selection: $entry.weightUnit) {
                                ForEach(WeightUnit.allCases) { unit in
                                    Text(unit.symbol).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .accessibilityIdentifier("SetDetail.WeightUnit")
                        }
                    }
                }

                if entry.exercise.metrics.usesReps {
                    OptionalIntegerField(title: "Reps", value: repsBinding, accessibilityIdentifier: "SetDetail.Reps")
                }

                if entry.exercise.metrics.usesDuration {
                    HStack {
                        Text("Duration")
                            .font(MarbleTypography.rowTitle)
                        Spacer()
                        DurationPicker(durationSeconds: durationBinding)
                            .accessibilityIdentifier("SetDetail.Duration")
                    }
                }
            } header: {
                SectionHeaderView(title: "Metrics")
            }

            Section {
                RPEPicker(value: $entry.difficulty)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .accessibilityIdentifier("SetDetail.RPE")
            }

            Section {
                RestPicker(restSeconds: $entry.restAfterSeconds)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .accessibilityIdentifier("SetDetail.RestPicker")
            }

            Section {
                DatePicker("Performed", selection: $entry.performedAt)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("SetDetail.PerformedAt")
            }

            Section {
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .marbleFieldStyle()
                    .accessibilityIdentifier("SetDetail.Notes")
            }

            Section {
                Button("Duplicate") {
                    duplicate()
                }
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("SetDetail.Duplicate")

                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                    dismiss()
                }
                .accessibilityIdentifier("SetDetail.Delete")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
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
            entry.updatedAt = AppEnvironment.now
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
