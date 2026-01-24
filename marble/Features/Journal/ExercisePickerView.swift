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

    var body: some View {
        List {
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

            Section {
                NavigationLink {
                    ManageExercisesView()
                } label: {
                    Label("Manage Exercises", systemImage: "slider.horizontal.3")
                }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Manage") {
                    ManageExercisesView()
                }
                .accessibilityIdentifier("ExercisePicker.Manage")
            }
        }
        .searchable(text: $searchText)
    }

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
            if !searchText.isEmpty, !exercise.name.localizedCaseInsensitiveContains(searchText) {
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

    private func exerciseRow(for exercise: Exercise) -> some View {
        let sanitizedName = exercise.name.replacingOccurrences(of: " ", with: "")
        return Button {
            selectedExercise = exercise
            dismiss()
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
                Image(systemName: exercise.category.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
                Text(exercise.name)
                    .font(MarbleTypography.rowTitle)
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .marbleRowInsets()
        .accessibilityIdentifier("ExercisePicker.Row.\(sanitizedName)")
    }
}
