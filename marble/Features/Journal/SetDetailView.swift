import SwiftUI
import SwiftData

struct SetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var entry: SetEntry

    @State private var addedLoad = false
    @State private var logReps = false
    @State private var logDistance = false
    @State private var logDuration = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExercisePickerView(selectedExercise: exerciseBinding)
                } label: {
                    HStack(spacing: MarbleLayout.rowSpacing) {
                        Text("Exercise")
                            .font(MarbleTypography.rowTitle)
                        Spacer()
                        HStack(spacing: MarbleSpacing.xs) {
                            ExerciseIconView(exercise: entry.exercise, fontSize: 18, frameSize: 24)
                            Text(entry.exercise.name)
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                }
                .accessibilityIdentifier("SetDetail.ExercisePicker")
            }

            Section {
                if entry.exercise.metrics.usesWeight {
                    if entry.exercise.metrics.weight == .optional {
                        Toggle(ExerciseMetricKind.weight.optionalToggleTitle, isOn: $addedLoad)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .onChange(of: addedLoad) { _, newValue in
                                if !newValue {
                                    entry.weight = nil
                                }
                            }
                            .accessibilityIdentifier("SetDetail.AddedLoad")
                    }

                    if shouldCaptureWeight {
                        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                            HStack {
                                OptionalNumberField(
                                    title: entry.exercise.weightInputTitle,
                                    formatter: Formatters.weight,
                                    value: weightBinding,
                                    accessibilityIdentifier: "SetDetail.Weight"
                                )
                                Picker("Unit", selection: $entry.weightUnit) {
                                    ForEach(WeightUnit.allCases) { unit in
                                        Text(unit.symbol).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(Theme.dividerColor(for: colorScheme))
                                .accessibilityIdentifier("SetDetail.WeightUnit")
                            }

                            Text(entry.exercise.weightInputHelperText)
                                .font(MarbleTypography.caption)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if entry.exercise.metrics.usesReps {
                    if entry.exercise.metrics.reps == .optional {
                        Toggle(ExerciseMetricKind.reps.optionalToggleTitle, isOn: $logReps)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .onChange(of: logReps) { _, newValue in
                                if newValue, entry.reps == nil {
                                    entry.reps = 10
                                }
                                if !newValue {
                                    entry.reps = nil
                                }
                            }
                            .accessibilityIdentifier("SetDetail.LogReps")
                    }

                    if shouldCaptureReps {
                        OptionalIntegerField(title: "Reps", value: repsBinding, accessibilityIdentifier: "SetDetail.Reps")
                    }
                }

                if entry.exercise.metrics.usesDistance {
                    if entry.exercise.metrics.distance == .optional {
                        Toggle(ExerciseMetricKind.distance.optionalToggleTitle, isOn: $logDistance)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .onChange(of: logDistance) { _, newValue in
                                if newValue, entry.distance == nil {
                                    entry.distance = 100
                                }
                                if !newValue {
                                    entry.distance = nil
                                }
                            }
                            .accessibilityIdentifier("SetDetail.LogDistance")
                    }

                    if shouldCaptureDistance {
                        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                            HStack {
                                OptionalNumberField(title: "Distance", formatter: Formatters.distance, value: distanceBinding, accessibilityIdentifier: "SetDetail.Distance")
                                Picker("Unit", selection: distanceUnitBinding) {
                                    ForEach(DistanceUnit.allCases) { unit in
                                        Text(unit.symbol.uppercased()).tag(unit)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.dividerColor(for: colorScheme))
                                .accessibilityIdentifier("SetDetail.DistanceUnit")
                            }

                            Text("Track this effort in \(entry.distanceUnit.title.lowercased()).")
                                .font(MarbleTypography.caption)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if entry.exercise.metrics.usesDuration {
                    if entry.exercise.metrics.durationSeconds == .optional {
                        Toggle(ExerciseMetricKind.duration.optionalToggleTitle, isOn: $logDuration)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .onChange(of: logDuration) { _, newValue in
                                if newValue, (entry.durationSeconds ?? 0) == 0 {
                                    entry.durationSeconds = 60
                                }
                                if !newValue {
                                    entry.durationSeconds = nil
                                }
                            }
                            .accessibilityIdentifier("SetDetail.LogDuration")
                    }

                    if shouldCaptureDuration {
                        HStack {
                            Text("Duration")
                                .font(MarbleTypography.rowTitle)
                            Spacer()
                            DurationPicker(durationSeconds: durationBinding)
                        }
                        .accessibilityElement(children: .contain)
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

            if let imported = entry.importedWorkout {
                importedSection(imported)
            }

            Section {
                Button("Duplicate") {
                    duplicate()
                }
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("SetDetail.Duplicate")

                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                    if modelContext.saveOrRollback() {
                        MarbleHaptics.warning()
                    }
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
        .marbleKeyboardToolbar()
        .onAppear {
            syncOptionalMetricState()
        }
        .onChange(of: entry.exercise) { _, newValue in
            syncOptionalMetricState(for: newValue)
        }
        .onDisappear {
            entry.updatedAt = AppEnvironment.now
            modelContext.saveOrRollback()
        }
    }

    /// Read-only provenance + workout-level stats for imported sets. The set's
    /// own metrics stay editable above; this is what the source recorded about
    /// the whole workout.
    @ViewBuilder
    private func importedSection(_ imported: ImportedWorkout) -> some View {
        Section {
            importedRow(label: "Origin", value: imported.displayOrigin)
            if let app = imported.sourceAppName, app != imported.displayOrigin {
                importedRow(label: "Via", value: app)
            }
            if let device = imported.deviceName {
                importedRow(label: "Device", value: device)
            }
            if let calories = imported.calories, calories > 0 {
                importedRow(label: "Calories", value: "\(Int(calories)) kcal")
            }
            if let average = imported.averageHeartRate, average > 0 {
                importedRow(label: "Avg Heart Rate", value: "\(Int(average)) bpm")
            }
            if let maximum = imported.maxHeartRate, maximum > 0 {
                importedRow(label: "Max Heart Rate", value: "\(Int(maximum)) bpm")
            }
            if let elevation = imported.elevationAscendedMeters, elevation > 0 {
                importedRow(label: "Elevation Gain", value: "\(Int(elevation)) m")
            }
            if let isIndoor = imported.isIndoor {
                importedRow(label: "Environment", value: isIndoor ? "Indoor" : "Outdoor")
            }
        } header: {
            SectionHeaderView(title: "Imported Workout")
        }
        .accessibilityIdentifier("SetDetail.Imported")
    }

    private func importedRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Spacer(minLength: MarbleSpacing.s)
            Text(value)
                .font(MarbleTypography.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
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
            get: { entry.exercise.displayedWeightInput(from: entry.weight) },
            set: { entry.weight = entry.exercise.storedWeight(from: $0) }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { entry.reps },
            set: { entry.reps = $0 }
        )
    }

    private var distanceBinding: Binding<Double?> {
        Binding(
            get: { entry.distance },
            set: { entry.distance = $0 }
        )
    }

    private var distanceUnitBinding: Binding<DistanceUnit> {
        Binding(
            get: { entry.distanceUnit },
            set: { entry.distanceUnit = $0 }
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

    private var shouldCaptureWeight: Bool {
        entry.exercise.metrics.weightIsRequired || (entry.exercise.metrics.weight == .optional && addedLoad)
    }

    private var shouldCaptureReps: Bool {
        entry.exercise.metrics.repsIsRequired || (entry.exercise.metrics.reps == .optional && logReps)
    }

    private var shouldCaptureDistance: Bool {
        entry.exercise.metrics.distanceIsRequired || (entry.exercise.metrics.distance == .optional && logDistance)
    }

    private var shouldCaptureDuration: Bool {
        entry.exercise.metrics.durationIsRequired || (entry.exercise.metrics.durationSeconds == .optional && logDuration)
    }

    private func duplicate() {
        let now = AppEnvironment.now
        let duplicate = SetEntry(
            exercise: entry.exercise,
            performedAt: now,
            weight: entry.weight,
            weightUnit: entry.weightUnit,
            reps: entry.reps,
            distance: entry.distance,
            distanceUnit: entry.distanceUnit,
            durationSeconds: entry.durationSeconds,
            difficulty: entry.difficulty,
            restAfterSeconds: entry.restAfterSeconds,
            notes: entry.notes,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(duplicate)
        if modelContext.saveOrRollback() {
            MarbleHaptics.success()
            RestActivityController.shared.startRest(for: duplicate)
        }
    }

    private func syncOptionalMetricState(for exercise: Exercise? = nil) {
        let currentExercise = exercise ?? entry.exercise
        addedLoad = currentExercise.metrics.weightIsRequired || entry.weight != nil
        logReps = currentExercise.metrics.repsIsRequired || entry.reps != nil
        logDistance = currentExercise.metrics.distanceIsRequired || entry.distance != nil
        logDuration = currentExercise.metrics.durationIsRequired || entry.durationSeconds != nil
    }
}
