import SwiftData
import SwiftUI

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SprintPrescription.createdAt)
    private var sprintPrescriptions: [SprintPrescription]

    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var editorDestination: ExerciseEditorDestination?
    @State private var showFavoriteError = false

    let onExerciseSaved: ((Exercise) -> Void)?

    init(onExerciseSaved: ((Exercise) -> Void)? = nil) {
        self.onExerciseSaved = onExerciseSaved
    }

    var body: some View {
        List {
            if filteredExercises.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(filteredExercises) { exercise in
                        exerciseRow(exercise)
                    }
                } header: {
                    Text(resultHeader)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ManageExercises.List")
        .navigationTitle("Exercise Library")
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
                Menu {
                    Button("All Exercises") { selectedCategory = nil }
                    Divider()
                    ForEach(ExerciseCategory.allCases) { category in
                        Button(category.displayName) { selectedCategory = category }
                    }
                } label: {
                    Label(filterLabel, systemImage: "line.3.horizontal.decrease")
                }
                .accessibilityIdentifier("ManageExercises.Filter")

                Button {
                    beginCreate(usingSearch: false)
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("ManageExercises.Add")
            }
        }
        .sheet(item: $editorDestination) { destination in
            ExerciseEditorView(
                exercise: destination.exercise,
                initialName: destination.initialName,
                onSave: { savedExercise in
                    editorDestination = nil
                    onExerciseSaved?(savedExercise)
                },
                onDelete: { editorDestination = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Unable to Update Favorite", isPresented: $showFavoriteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Marble couldn't update this exercise. Please try again.")
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = trimmedSearchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(trimmedSearchText)
            let matchesCategory = selectedCategory == nil || exercise.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var resultHeader: String {
        let count = filteredExercises.count
        if let selectedCategory {
            return "\(selectedCategory.displayName) · \(count)"
        }
        return "\(count) \(count == 1 ? "Exercise" : "Exercises")"
    }

    private var filterLabel: String {
        selectedCategory?.displayName ?? "Filter"
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label("No Exercises Found", systemImage: "magnifyingglass")
            } description: {
                Text(emptyDescription)
            } actions: {
                Button(createButtonTitle) {
                    beginCreate(usingSearch: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryTextColor(for: colorScheme))
                .accessibilityIdentifier("ManageExercises.CreateFromSearch")
            }
            .listRowSeparator(.hidden)
        }
    }

    private var emptyDescription: String {
        if selectedCategory != nil, trimmedSearchText.isEmpty {
            return "No exercises use this category yet."
        }
        return trimmedSearchText.isEmpty
            ? "Create your first exercise to start building your library."
            : "Try another search or create \"\(trimmedSearchText)\"."
    }

    private var createButtonTitle: String {
        trimmedSearchText.isEmpty ? "Add Exercise" : "Create \"\(trimmedSearchText)\""
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let summary = exercise.librarySummary(prescription: prescription(for: exercise))
        let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
        return Button {
            editorDestination = .edit(exercise)
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
                                .accessibilityLabel("Favorite")
                        }
                    }
                    Text("\(exercise.category.displayName) · \(summary)")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleFavorite(exercise)
            } label: {
                Label(exercise.isFavorite ? "Unfavorite" : "Favorite", systemImage: exercise.isFavorite ? "star.slash" : "star")
            }
            .tint(.gray)
        }
        .accessibilityIdentifier("ManageExercises.Row.\(sanitizedName)")
        .accessibilityLabel(exercise.name)
        .accessibilityValue("\(exercise.category.displayName), \(summary)\(exercise.isFavorite ? ", favorite" : "")")
    }

    private func prescription(for exercise: Exercise) -> SprintPrescription? {
        sprintPrescriptions.first { $0.exerciseID == exercise.id }
    }

    private func beginCreate(usingSearch: Bool) {
        selectedCategory = nil
        editorDestination = .create(initialName: usingSearch ? trimmedSearchText : "")
    }

    private func toggleFavorite(_ exercise: Exercise) {
        exercise.isFavorite.toggle()
        guard modelContext.saveOrRollback() else {
            showFavoriteError = true
            return
        }
        MarbleHaptics.selection()
    }
}

private struct ExerciseEditorDestination: Identifiable {
    let id = UUID()
    let exercise: Exercise?
    let initialName: String

    static func create(initialName: String) -> ExerciseEditorDestination {
        ExerciseEditorDestination(exercise: nil, initialName: initialName)
    }

    static func edit(_ exercise: Exercise) -> ExerciseEditorDestination {
        ExerciseEditorDestination(exercise: exercise, initialName: "")
    }
}
