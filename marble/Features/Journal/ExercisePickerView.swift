import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedExercise: Exercise?

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var recentEntries: [SetEntry]

    @State private var searchText: String = ""
    @State private var createDraftName: String = ""
    @State private var showCreateExercise = false
    @State private var showManageExercises = false
    @State private var pendingSavedExercise: Exercise?

    var body: some View {
        List {
            if canShowCreateShortcut {
                Section {
                    Button {
                        createDraftName = trimmedSearchText
                        showCreateExercise = true
                    } label: {
                        createExerciseRow
                    }
                    .buttonStyle(.plain)
                    .marbleRowInsets()
                    .accessibilityIdentifier(trimmedSearchText.isEmpty ? "ExercisePicker.Create" : "ExercisePicker.CreateFromSearch")
                } header: {
                    SectionHeaderView(title: "Add New")
                }
            }

            if !recents.isEmpty {
                Section {
                    ForEach(recents) { exercise in
                        exerciseRow(for: exercise)
                    }
                } header: {
                    SectionHeaderView(title: "Recents")
                }
            }

            if !favorites.isEmpty {
                Section {
                    ForEach(favorites) { exercise in
                        exerciseRow(for: exercise)
                    }
                } header: {
                    SectionHeaderView(title: "Favorites")
                }
            }

            if filteredExercises.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Text("No exercises match that search yet.")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text("Create it here so the next time you log, it already behaves the way you want.")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xs)
                    .marbleRowInsets()
                    .accessibilityIdentifier("ExercisePicker.EmptyState")
                }
            } else {
                ForEach(ExerciseCategory.allCases) { category in
                    let categoryExercises = filteredExercises.filter { $0.category == category }
                    if !categoryExercises.isEmpty {
                        Section {
                            ForEach(categoryExercises) { exercise in
                                exerciseRow(for: exercise)
                            }
                        } header: {
                            SectionHeaderView(title: category.displayName)
                        }
                    }
                }
            }

            Section {
                Button {
                    showManageExercises = true
                } label: {
                    Label("Manage all exercises", systemImage: "slider.horizontal.3")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }
                .buttonStyle(.plain)
                .marbleRowInsets()
                .accessibilityIdentifier("ExercisePicker.ManageRow")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ExercisePicker.List")
        .navigationTitle("Exercises")
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
                Button("Manage") {
                    showManageExercises = true
                }
                .accessibilityIdentifier("ExercisePicker.Manage")
            }
        }
        .navigationDestination(isPresented: $showManageExercises) {
            ManageExercisesView(onExerciseSaved: handleSavedExerciseFromManage)
        }
        .navigationDestination(isPresented: $showCreateExercise) {
            ExerciseEditorView(
                exercise: nil,
                initialName: createDraftName
            ) { exercise in
                selectedExercise = exercise
            }
        }
        .onChange(of: showManageExercises) { _, isShowingManageExercises in
            guard !isShowingManageExercises, let pendingSavedExercise else { return }
            self.pendingSavedExercise = nil
            selectedExercise = pendingSavedExercise
        }
        .onChange(of: showCreateExercise) { _, isShowingCreateExercise in
            guard !isShowingCreateExercise, selectedExercise != nil else { return }
            dismiss()
        }
        .onChange(of: selectedExercise?.id) { _, newValue in
            if newValue != nil, !showCreateExercise {
                dismiss()
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExactMatch: Bool {
        filteredExercises.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedSearchText) == .orderedSame
        }
    }

    private var canShowCreateShortcut: Bool {
        trimmedSearchText.isEmpty || !hasExactMatch
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

    private var recents: [Exercise] {
        var seen = Set<UUID>()
        var unique: [Exercise] = []
        for entry in recentEntries {
            let exercise = entry.exercise
            if seen.contains(exercise.id) {
                continue
            }
            if !trimmedSearchText.isEmpty, !exercise.name.localizedCaseInsensitiveContains(trimmedSearchText) {
                continue
            }
            seen.insert(exercise.id)
            unique.append(exercise)
            if unique.count >= 5 {
                break
            }
        }
        return unique
    }

    private var createExerciseRow: some View {
        HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            Image(systemName: "plus.circle")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(trimmedSearchText.isEmpty ? "Create New Exercise" : "Create \"\(trimmedSearchText)\"")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text("Name it, choose what you'll log, and jump straight back into the set logger.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exerciseRow(for exercise: Exercise) -> some View {
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
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .marbleRowInsets()
        .accessibilityIdentifier("ExercisePicker.Row.\(sanitizedName)")
        .accessibilityValue(exercise.configurationSummaryText)
    }

    private func handleSavedExerciseFromManage(_ exercise: Exercise) {
        searchText = exercise.name
        pendingSavedExercise = exercise
        showManageExercises = false
    }
}
