import SwiftUI
import SwiftData

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var showingNewExercise = false
    @State private var showCannotDelete = false
    @State private var showDeleteError = false
    @State private var cannotDeleteName = ""
    @State private var searchText: String = ""
    @State private var newExerciseSeedName = ""
    @State private var pendingSavedExercise: Exercise?
    @State private var editingExercise: Exercise?

    let onExerciseSaved: ((Exercise) -> Void)?

    init(onExerciseSaved: ((Exercise) -> Void)? = nil) {
        self.onExerciseSaved = onExerciseSaved
    }

    var body: some View {
        List {
            if filteredExercises.isEmpty {
                Section {
                    Button {
                        newExerciseSeedName = trimmedSearchText
                        showingNewExercise = true
                    } label: {
                        Label(
                            trimmedSearchText.isEmpty ? "Create New Exercise" : "Create \"\(trimmedSearchText)\"",
                            systemImage: "plus.circle"
                        )
                    }
                    .accessibilityIdentifier("ManageExercises.CreateFromSearch")
                } footer: {
                    Text("No exercises match that search.")
                }
            } else {
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { exercise in
                            exerciseRow(for: exercise)
                        }
                    }
                }

                ForEach(categoriesWithExercises) { category in
                    Section(category.displayName) {
                        ForEach(categorizedExercises[category] ?? []) { exercise in
                            exerciseRow(for: exercise)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("ManageExercises.List")
        .navigationTitle("Manage Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .minimizeSearchToolbarWhenAvailable()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newExerciseSeedName = trimmedSearchText
                    showingNewExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageExercises.Add")
            }
        }
        .sheet(isPresented: $showingNewExercise, onDismiss: handleCreateDismissed) {
            NavigationStack {
                ExerciseEditorView(exercise: nil, initialName: newExerciseSeedName) { exercise in
                    searchText = exercise.name
                    pendingSavedExercise = exercise
                }
            }
        }
        .navigationDestination(item: $editingExercise) { exercise in
            ExerciseEditorView(exercise: exercise) { _ in
                editingExercise = nil
            }
        }
        .alert("Cannot Delete Exercise", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(cannotDeleteName)\" has logged sets. Remove those sets before deleting.")
        }
        .alert("Unable to Delete Exercise", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't delete that exercise right now. Please try again.")
        }
    }

    private func exerciseRow(for exercise: Exercise) -> some View {
        let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
        return Button {
            editingExercise = exercise
        } label: {
            HStack(spacing: MarbleSpacing.s) {
                ExerciseIconView(exercise: exercise, fontSize: 18, frameSize: MarbleLayout.rowIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: MarbleSpacing.xs) {
                        Text(exercise.name)
                            .foregroundStyle(.primary)
                        if exercise.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(rowSubtitle(for: exercise))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ManageExercises.Row.\(sanitizedName)")
        .accessibilityValue(rowSubtitle(for: exercise))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                attemptDelete(exercise)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("ManageExercises.Row.\(sanitizedName).Delete")
        }
    }

    private func rowSubtitle(for exercise: Exercise) -> String {
        let metrics = exercise.metrics.previewTitle
        let rest = DateHelper.formattedDuration(seconds: exercise.defaultRestSeconds)
        return "\(metrics) · rest \(rest)"
    }

    // MARK: - Derived state

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExercises: [Exercise] {
        if trimmedSearchText.isEmpty {
            return exercises
        }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var favorites: [Exercise] {
        filteredExercises.filter { $0.isFavorite }
    }

    private var categorizedExercises: [ExerciseCategory: [Exercise]] {
        Dictionary(grouping: filteredExercises.filter { !$0.isFavorite }) { $0.category }
    }

    private var categoriesWithExercises: [ExerciseCategory] {
        ExerciseCategory.allCases.filter { !(categorizedExercises[$0] ?? []).isEmpty }
    }

    // MARK: - Actions

    private func attemptDelete(_ exercise: Exercise) {
        let count = entries.filter { $0.exercise.id == exercise.id }.count
        if count > 0 {
            cannotDeleteName = exercise.name
            showCannotDelete = true
            return
        }

        modelContext.delete(exercise)
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Delete exercise failed: \(error)")
            #endif
            modelContext.rollback()
            showDeleteError = true
        }
    }

    private func handleCreateDismissed() {
        guard let exercise = pendingSavedExercise else { return }
        pendingSavedExercise = nil
        onExerciseSaved?(exercise)
    }
}
