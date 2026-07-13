import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedExercise: Exercise?

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var recentEntries: [SetEntry]

    @Query(sort: \SprintPrescription.createdAt)
    private var sprintPrescriptions: [SprintPrescription]

    @State private var searchText = ""
    @State private var showManageExercises = false
    @State private var editorDestination: PickerEditorDestination?

    var body: some View {
        List {
            if trimmedSearchText.isEmpty {
                if exercises.isEmpty {
                    firstExerciseSection
                } else if !recents.isEmpty {
                    exerciseSection(title: "Recent", exercises: recents)
                }
                if !favoriteRemainder.isEmpty {
                    exerciseSection(title: "Favorites", exercises: favoriteRemainder)
                }
                if !allRemainder.isEmpty {
                    exerciseSection(title: "All Exercises", exercises: allRemainder)
                }
            } else if filteredExercises.isEmpty {
                noResultsSection
            } else {
                if !hasExactMatch {
                    createSearchSection
                }
                exerciseSection(title: "Results", exercises: filteredExercises)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ExercisePicker.List")
        .navigationTitle("Choose Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Manage") {
                    showManageExercises = true
                }
                .accessibilityIdentifier("ExercisePicker.Manage")

                Button {
                    editorDestination = PickerEditorDestination(initialName: createSeedName)
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("ExercisePicker.Create")
            }
        }
        .navigationDestination(isPresented: $showManageExercises) {
            ManageExercisesView { exercise in
                selectedExercise = exercise
                showManageExercises = false
                DispatchQueue.main.async { dismiss() }
            }
        }
        .sheet(item: $editorDestination) { destination in
            ExerciseEditorView(
                exercise: nil,
                initialName: destination.initialName
            ) { exercise in
                selectedExercise = exercise
                editorDestination = nil
                DispatchQueue.main.async { dismiss() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExactMatch: Bool {
        exercises.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedSearchText) == .orderedSame
        }
    }

    private var createSeedName: String {
        hasExactMatch ? "" : trimmedSearchText
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var recents: [Exercise] {
        var seen = Set<UUID>()
        return recentEntries.compactMap { entry in
            guard seen.insert(entry.exercise.id).inserted else { return nil }
            return entry.exercise
        }.prefix(5).map { $0 }
    }

    private var favoriteRemainder: [Exercise] {
        let recentIDs = Set(recents.map(\.id))
        return exercises.filter { $0.isFavorite && !recentIDs.contains($0.id) }
    }

    private var allRemainder: [Exercise] {
        let featuredIDs = Set((recents + favoriteRemainder).map(\.id))
        return exercises.filter { !featuredIDs.contains($0.id) }
    }

    private var noResultsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                Label("No Exercise Found", systemImage: "magnifyingglass")
                    .font(MarbleTypography.rowTitle)
                Text("Create \"\(trimmedSearchText)\" and Marble will return it to this set.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ExercisePicker.EmptyState")

            Button {
                editorDestination = PickerEditorDestination(initialName: trimmedSearchText)
            } label: {
                Label("Create \"\(trimmedSearchText)\"", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityIdentifier("ExercisePicker.CreateFromSearch")
        }
    }

    private var firstExerciseSection: some View {
        Section {
            ContentUnavailableView {
                Label("Build Your Exercise Library", systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("Create an exercise once, then reuse it whenever you log a workout.")
            } actions: {
                Button("Create Exercise") {
                    editorDestination = PickerEditorDestination(initialName: "")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("ExercisePicker.CreateFirst")
            }
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("ExercisePicker.FirstExerciseState")
        }
    }

    private var createSearchSection: some View {
        Section {
            Button {
                editorDestination = PickerEditorDestination(initialName: trimmedSearchText)
            } label: {
                Label("Create \"\(trimmedSearchText)\"", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("ExercisePicker.CreateFromSearch")
        }
    }

    private func exerciseSection(title: String, exercises: [Exercise]) -> some View {
        Section(title) {
            ForEach(exercises) { exercise in
                exerciseRow(exercise)
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let summary = exercise.librarySummary(prescription: prescription(for: exercise))
        let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
        return Button {
            selectedExercise = exercise
            dismiss()
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
                ExerciseIconView(exercise: exercise, fontSize: 18, frameSize: MarbleLayout.rowIconSize)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    HStack(spacing: MarbleSpacing.xs) {
                        Text(exercise.name)
                            .font(MarbleTypography.rowTitle)
                        if exercise.isFavorite {
                            Image(systemName: "star.fill")
                                .font(MarbleTypography.rowMeta)
                                .accessibilityHidden(true)
                        }
                    }
                    Text("\(exercise.category.displayName) · \(summary)")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .accessibilityIdentifier("ExercisePicker.Row.\(sanitizedName)")
        .accessibilityLabel(exercise.name)
        .accessibilityValue("\(exercise.category.displayName), \(summary)\(exercise.isFavorite ? ", favorite" : "")")
    }

    private func prescription(for exercise: Exercise) -> SprintPrescription? {
        sprintPrescriptions.first { $0.exerciseID == exercise.id }
    }
}

private struct PickerEditorDestination: Identifiable {
    let id = UUID()
    let initialName: String
}
