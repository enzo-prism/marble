import SwiftUI
import SwiftData

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

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

    let onExerciseSaved: ((Exercise) -> Void)?

    init(onExerciseSaved: ((Exercise) -> Void)? = nil) {
        self.onExerciseSaved = onExerciseSaved
    }

    var body: some View {
        List {
            if filteredExercises.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text("No exercises match that search.")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Button {
                            newExerciseSeedName = trimmedSearchText
                            showingNewExercise = true
                        } label: {
                            Text(trimmedSearchText.isEmpty ? "Create New Exercise" : "Create \"\(trimmedSearchText)\"")
                        }
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                        .accessibilityIdentifier("ManageExercises.CreateFromSearch")
                    }
                    .padding(.vertical, MarbleSpacing.xs)
                    .marbleRowInsets()
                }
            } else {
                ForEach(filteredExercises) { exercise in
                    let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
                    NavigationLink {
                        ExerciseEditorView(exercise: exercise)
                    } label: {
                        HStack(spacing: MarbleLayout.rowSpacing) {
                            ExerciseIconView(exercise: exercise, fontSize: 18, frameSize: MarbleLayout.rowIconSize)

                            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                                HStack(spacing: MarbleSpacing.xs) {
                                    Text(exercise.name)
                                        .font(MarbleTypography.rowTitle)
                                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                                    if exercise.isFavorite {
                                        Image(systemName: "star.fill")
                                            .font(MarbleTypography.rowMeta)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                            .accessibilityHidden(true)
                                    }
                                }

                                Text(exercise.configurationSummaryText)
                                    .font(MarbleTypography.rowMeta)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .marbleRowInsets()
                    .accessibilityIdentifier("ManageExercises.Row.\(sanitizedName)")
                }
                .onDelete(perform: deleteExercises)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ManageExercises.List")
        .navigationTitle("Manage Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .searchToolbarBehavior(.minimize)
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

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExercises: [Exercise] {
        if trimmedSearchText.isEmpty {
            return exercises
        }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            let exercise = filteredExercises[index]
            let count = entries.filter { $0.exercise.id == exercise.id }.count
            if count > 0 {
                cannotDeleteName = exercise.name
                showCannotDelete = true
                continue
            }
            modelContext.delete(exercise)
        }

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
