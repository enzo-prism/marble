import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @Binding var selectedExercise: Exercise?

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    // Bounded window (newest ~200 rows) instead of the previous unbounded
    // all-history query: recents only need the first few distinct exercises,
    // and the rare saturated window pages deeper inside the memo (see
    // `pickerData`). Inserts and edits made while the sheet is up still land
    // — new logs refresh both this window and the one-row updatedAt probe.
    @Query(SetEntryQueries.recentEntriesForPicker)
    private var recentEntries: [SetEntry]

    @Query(sort: \SprintPrescription.createdAt)
    private var sprintPrescriptions: [SprintPrescription]

    @Query(LatestUpdateQueries.setEntry)
    private var latestUpdatedEntries: [SetEntry]

    @State private var searchText = ""
    @State private var showManageExercises = false
    @State private var editorDestination: PickerEditorDestination?
    @State private var derivedMemo = RenderMemo<ExercisePickerSignature, ExercisePickerDerivedData>()

    var body: some View {
        let derived = pickerData
        List {
            if trimmedSearchText.isEmpty {
                if exercises.isEmpty {
                    firstExerciseSection
                } else if !derived.recents.isEmpty {
                    exerciseSection(title: "Recent", exercises: derived.recents, prescriptions: derived.prescriptions)
                }
                if !derived.favoriteRemainder.isEmpty {
                    exerciseSection(title: "Favorites", exercises: derived.favoriteRemainder, prescriptions: derived.prescriptions)
                }
                if !derived.allRemainder.isEmpty {
                    exerciseSection(title: "All Exercises", exercises: derived.allRemainder, prescriptions: derived.prescriptions)
                }
            } else if filteredExercises.isEmpty {
                noResultsSection
            } else {
                if !hasExactMatch {
                    createSearchSection
                }
                exerciseSection(title: "Results", exercises: filteredExercises, prescriptions: derived.prescriptions)
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

    private var pickerData: ExercisePickerDerivedData {
        let signature = ExercisePickerSignature(
            entryCount: recentEntries.count,
            latestEntryUpdate: latestUpdatedEntries.first?.updatedAt ?? .distantPast,
            exerciseOrder: exercises.map(\.id),
            favoriteExerciseIDs: exercises.filter(\.isFavorite).map(\.id),
            prescriptionOwners: sprintPrescriptions.map {
                ExercisePickerSignature.PrescriptionOwner(id: $0.id, exerciseID: $0.exerciseID)
            }
        )
        return derivedMemo.value(for: signature) {
            // Escalates past the bounded window only when it is saturated by
            // fewer distinct exercises than the Recent row shows — and only
            // here, on a memo miss, never per keystroke or render.
            let entriesForRecents = SetEntryQueries.entriesForPickerRecents(
                window: recentEntries,
                minimumDistinct: ExercisePickerDerivedData.recentLimit,
                in: modelContext
            )
            return ExercisePickerDerivedData.build(
                exercises: exercises,
                recentEntries: entriesForRecents,
                sprintPrescriptions: sprintPrescriptions
            )
        }
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

    private func exerciseSection(
        title: String,
        exercises: [Exercise],
        prescriptions: [UUID: SprintPrescription]
    ) -> some View {
        Section(title) {
            ForEach(exercises) { exercise in
                exerciseRow(exercise, prescription: prescriptions[exercise.id])
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise, prescription: SprintPrescription?) -> some View {
        let summary = exercise.librarySummary(prescription: prescription)
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

}

struct ExercisePickerDerivedData {
    /// How many distinct exercises the Recent row shows. Also the coverage
    /// target the scoped recents fetch must satisfy (see
    /// `SetEntryQueries.entriesForPickerRecents`). `nonisolated` so it can
    /// appear in `build`'s default argument regardless of caller isolation.
    nonisolated static let recentLimit = 5

    let recents: [Exercise]
    let favoriteRemainder: [Exercise]
    let allRemainder: [Exercise]
    let prescriptions: [UUID: SprintPrescription]

    static func build(
        exercises: [Exercise],
        recentEntries: [SetEntry],
        sprintPrescriptions: [SprintPrescription],
        recentLimit: Int = ExercisePickerDerivedData.recentLimit
    ) -> ExercisePickerDerivedData {
        var seen = Set<UUID>()
        var recents: [Exercise] = []
        recents.reserveCapacity(min(recentLimit, exercises.count))

        for entry in recentEntries {
            guard recents.count < recentLimit else { break }
            guard seen.insert(entry.exercise.id).inserted else { continue }
            recents.append(entry.exercise)
        }

        let recentIDs = Set(recents.map(\.id))
        let favorites = exercises.filter { $0.isFavorite && !recentIDs.contains($0.id) }
        let featuredIDs = recentIDs.union(favorites.map(\.id))
        let remainder = exercises.filter { !featuredIDs.contains($0.id) }
        let prescriptions = Dictionary(
            sprintPrescriptions.map { ($0.exerciseID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return ExercisePickerDerivedData(
            recents: recents,
            favoriteRemainder: favorites,
            allRemainder: remainder,
            prescriptions: prescriptions
        )
    }
}

private struct ExercisePickerSignature: Equatable {
    struct PrescriptionOwner: Equatable {
        let id: UUID
        let exerciseID: UUID
    }

    /// Count of the *bounded* recents window (≤ `pickerRecentScanLimit`), not
    /// the whole table. Together with `latestEntryUpdate` this catches every
    /// change a user can make while the picker sheet is up (logging stamps a
    /// fresh `updatedAt`); a deletion of a row beyond the window can stay
    /// stale until the next signature change — the same accepted staleness as
    /// the Trends history fetch (see `TrendsView.fetchHistoryEntries`), and
    /// no journal-delete UI is reachable while this sheet is presented.
    let entryCount: Int
    let latestEntryUpdate: Date
    let exerciseOrder: [UUID]
    let favoriteExerciseIDs: [UUID]
    let prescriptionOwners: [PrescriptionOwner]
}

private struct PickerEditorDestination: Identifiable {
    let id = UUID()
    let initialName: String
}
