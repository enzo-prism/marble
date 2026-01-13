import SwiftUI
import SwiftData

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let exercise: Exercise?

    @State private var name: String = ""
    @State private var category: ExerciseCategory = .chest
    @State private var weightRequirement: MetricRequirement = .none
    @State private var repsRequirement: MetricRequirement = .required
    @State private var durationRequirement: MetricRequirement = .none
    @State private var defaultRestSeconds: Int = 60
    @State private var isFavorite: Bool = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .marbleFieldStyle()
                    .accessibilityIdentifier("ExerciseEditor.Name")
                Picker("Category", selection: $category) {
                    ForEach(ExerciseCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .accessibilityIdentifier("ExerciseEditor.Category")
                Toggle("Favorite", isOn: $isFavorite)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("ExerciseEditor.Favorite")
            } header: {
                SectionHeaderView(title: "Basics")
            }

            Section {
                requirementPicker(title: "Weight", selection: $weightRequirement)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("ExerciseEditor.Metric.Weight")
                requirementPicker(title: "Reps", selection: $repsRequirement)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("ExerciseEditor.Metric.Reps")
                requirementPicker(title: "Duration", selection: $durationRequirement)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("ExerciseEditor.Metric.Duration")
            } header: {
                SectionHeaderView(title: "Metrics")
            }

            Section {
                Stepper(value: $defaultRestSeconds, in: 0...600, step: 15) {
                    Text("Rest \(DateHelper.formattedDuration(seconds: defaultRestSeconds))")
                }
                .accessibilityIdentifier("ExerciseEditor.DefaultRest")
            } header: {
                SectionHeaderView(title: "Defaults")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ExerciseEditor.Save")
            }
        }
        .onAppear {
            if let exercise {
                load(from: exercise)
            }
        }
    }

    private func requirementPicker(title: String, selection: Binding<MetricRequirement>) -> some View {
        Picker(title, selection: selection) {
            Text("Off").tag(MetricRequirement.none)
            Text("Optional").tag(MetricRequirement.optional)
            Text("Required").tag(MetricRequirement.required)
        }
        .pickerStyle(.segmented)
    }

    private func load(from exercise: Exercise) {
        name = exercise.name
        category = exercise.category
        weightRequirement = exercise.metrics.weight
        repsRequirement = exercise.metrics.reps
        durationRequirement = exercise.metrics.durationSeconds
        defaultRestSeconds = exercise.defaultRestSeconds
        isFavorite = exercise.isFavorite
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = ExerciseMetricsProfile(
            weight: weightRequirement,
            reps: repsRequirement,
            durationSeconds: durationRequirement
        )

        if let exercise {
            exercise.name = trimmedName
            exercise.category = category
            exercise.metrics = metrics
            exercise.defaultRestSeconds = defaultRestSeconds
            exercise.isFavorite = isFavorite
        } else {
            let newExercise = Exercise(
                name: trimmedName,
                category: category,
                metrics: metrics,
                defaultRestSeconds: defaultRestSeconds,
                isFavorite: isFavorite
            )
            modelContext.insert(newExercise)
        }

        dismiss()
    }
}
