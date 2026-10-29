import SwiftUI

struct TrendsExerciseSearchView: View {
    let exercises: [Exercise]
    let entries: [SetEntry]
    @Binding var selectedExerciseID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                allExercisesRow
            }

            if trimmedSearchText.isEmpty, !recentExercises.isEmpty {
                Section {
                    ForEach(recentExercises) { exercise in
                        exerciseRow(for: exercise)
                    }
                } header: {
                    SectionHeaderView(title: "Recent")
                }
            }

            if filteredExercises.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Text("No exercises match that search.")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text("Clear the search or choose All Exercises to see the full trend view.")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    .padding(.vertical, MarbleSpacing.xs)
                    .marbleRowInsets()
                    .accessibilityIdentifier("Trends.ExerciseSearch.EmptyState")
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
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Trends.ExerciseSearch.List")
        .navigationTitle("Filter Exercise")
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
                Button("Done") {
                    dismiss()
                }
                .accessibilityIdentifier("Trends.ExerciseSearch.Done")
            }
        }
    }

    private var allExercisesRow: some View {
        Button {
            selectedExerciseID = nil
            dismiss()
        } label: {
            HStack(spacing: MarbleLayout.rowSpacing) {
                ScaledSymbol(systemName: "line.3.horizontal.decrease.circle", size: 18, weight: .semibold, frameSize: MarbleLayout.rowIconSize)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text("All Exercises")
                        .font(MarbleTypography.rowTitle)
                    Text("Show every logged set in Trends.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if selectedExerciseID == nil {
                    Image(systemName: "checkmark")
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .accessibilityIdentifier("Trends.ExerciseSearch.All")
        .accessibilityValue(selectedExerciseID == nil ? "Selected" : "Not selected")
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

    private var recentExercises: [Exercise] {
        var seen = Set<UUID>()
        var unique: [Exercise] = []
        let availableIDs = Set(exercises.map(\.id))

        for entry in entries {
            let exercise = entry.exercise
            guard availableIDs.contains(exercise.id), !seen.contains(exercise.id) else { continue }
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
            selectedExerciseID = exercise.id
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

                if selectedExerciseID == exercise.id {
                    Image(systemName: "checkmark")
                        .font(MarbleTypography.rowMeta.weight(.semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .accessibilityIdentifier("Trends.ExerciseSearch.Row.\(sanitizedName)")
        .accessibilityValue(exercise.configurationSummaryText)
    }
}
