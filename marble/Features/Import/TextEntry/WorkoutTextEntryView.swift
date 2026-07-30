import SwiftData
import SwiftUI

/// The end-to-end "type or paste a workout" flow: free text → on-device parse →
/// review matches/edit → add to journal. Presented as a sheet from the import
/// screen; the review step is the scan flow's reviewer plus per-exercise library
/// matching, so the user approves exactly which rows are reused or created.
struct WorkoutTextEntryView: View {
    @State private var viewModel = WorkoutTextEntryViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .background(Theme.backgroundColor(for: colorScheme))
                .navigationTitle("Type a Workout")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar { toolbarContent }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .input: inputView
        case .processing: processingView
        case .review: reviewView
        case .imported: importedView
        }
    }

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                Text("Describe your workout in your own words — exercises, weight, reps, and rest. Marble reads it on your device and turns it into sets you can review before logging.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $viewModel.text)
                    .font(MarbleTypography.rowSubtitle)
                    .focused($textFocused)
                    .scrollContentBackground(.hidden)
                    .padding(MarbleSpacing.s)
                    .frame(minHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.chipFillColor(for: colorScheme))
                    )
                    .overlay(alignment: .topLeading) {
                        if viewModel.text.isEmpty {
                            Text("Push day\nBench press 3x8 @ 185, rest 90s\nIncline DB press 3x10 @ 60\nCable fly 3x12\nPlank 3x45s")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.6))
                                .padding(MarbleSpacing.s)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("TextEntry.Editor")

                Button {
                    textFocused = false
                    Task { await viewModel.preview(in: modelContext) }
                } label: {
                    Text("Preview Workout")
                }
                .buttonStyle(MarbleActionButtonStyle(
                    isEnabledOverride: !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    expandsHorizontally: true,
                    prominence: .primary
                ))
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("TextEntry.Preview")

                Label(
                    viewModel.usesOnDeviceModel
                        ? "Read on your device with Apple Intelligence — nothing is uploaded."
                        : "Read on your device — nothing is uploaded.",
                    systemImage: "lock.fill"
                )
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.Error")
                }
            }
            .padding(MarbleSpacing.m)
        }
        .accessibilityIdentifier("TextEntry.Input")
    }

    private var processingView: some View {
        VStack(spacing: MarbleSpacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your workout…")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("TextEntry.Processing")
    }

    private var reviewView: some View {
        List {
            Section {
                TextField("Workout title", text: $viewModel.draft.title)
                    .font(MarbleTypography.rowTitle)
                    .accessibilityIdentifier("TextEntry.Title")
                DatePicker("Date", selection: performedAtBinding, displayedComponents: .date)
                    .accessibilityIdentifier("TextEntry.Date")
            } header: {
                SectionHeaderView(title: "Workout")
            }

            if viewModel.alreadyImported {
                Section {
                    Label("This workout text was already added to your journal. Importing again will add the sets a second time.", systemImage: "exclamationmark.triangle")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.AlreadyImported")
                }
            }

            ForEach($viewModel.draft.exercises) { $exercise in
                TextEntryExerciseSection(
                    exercise: $exercise,
                    resolution: viewModel.resolution(for: exercise.id),
                    onChoose: { choice in viewModel.choose(choice, for: exercise.id) },
                    onNameChanged: { viewModel.refreshResolution(forExerciseWithID: exercise.id) },
                    onAddSet: { viewModel.addSet(toExerciseWithID: exercise.id) },
                    onRemoveExercise: { viewModel.removeExercise(withID: exercise.id) },
                    onRemoveSets: { offsets in viewModel.removeSets(fromExerciseWithID: exercise.id, at: offsets) }
                )
            }

            Section {
                Button {
                    viewModel.addExercise()
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("TextEntry.AddExercise")

                if viewModel.newExerciseCount > 0 {
                    Text("\(viewModel.newExerciseCount) new exercise\(viewModel.newExerciseCount == 1 ? "" : "s") will be added to your library.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.NewExerciseSummary")
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.Error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .safeAreaInset(edge: .bottom) {
            importButton
        }
        .accessibilityIdentifier("TextEntry.Review")
    }

    private var importButton: some View {
        Button {
            viewModel.commit(into: modelContext)
        } label: {
            Text(importButtonTitle)
        }
        .buttonStyle(MarbleActionButtonStyle(
            isEnabledOverride: viewModel.draft.hasContent,
            expandsHorizontally: true,
            prominence: .primary
        ))
        .disabled(!viewModel.draft.hasContent)
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.bottom, MarbleSpacing.s)
        .accessibilityIdentifier("TextEntry.Import")
    }

    private var importButtonTitle: String {
        let count = viewModel.draft.totalSetCount
        guard count > 0 else { return "Add to Journal" }
        return "Add \(count) set\(count == 1 ? "" : "s") to Journal"
    }

    private var importedView: some View {
        VStack(spacing: MarbleSpacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            if let summary = viewModel.lastSummary {
                Text("Added \(summary.importedSets) set\(summary.importedSets == 1 ? "" : "s")")
                    .font(MarbleTypography.emptyTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                if summary.createdExercises > 0 {
                    Text("\(summary.createdExercises) new exercise\(summary.createdExercises == 1 ? "" : "s") added to your library.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                if summary.skipped > 0 {
                    Text("This workout was already imported.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            Button("Done") { dismiss() }
                .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                .accessibilityIdentifier("TextEntry.ImportedDone")
                .padding(.top, MarbleSpacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MarbleSpacing.l)
        .accessibilityIdentifier("TextEntry.Imported")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(viewModel.phase == .review ? "Cancel" : "Done") { dismiss() }
                .accessibilityIdentifier("TextEntry.Dismiss")
        }
        if viewModel.phase == .review {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Text") { viewModel.editText() }
                    .accessibilityIdentifier("TextEntry.EditText")
            }
        }
    }

    private var performedAtBinding: Binding<Date> {
        Binding(
            get: { viewModel.draft.performedAt ?? AppEnvironment.now },
            set: { viewModel.draft.performedAt = $0 }
        )
    }
}

// MARK: - Exercise section

private struct TextEntryExerciseSection: View {
    @Binding var exercise: ParsedExerciseDraft
    let resolution: WorkoutTextEntryViewModel.Resolution?
    var onChoose: (WorkoutTextEntryViewModel.Resolution.Choice) -> Void
    var onNameChanged: () -> Void
    var onAddSet: () -> Void
    var onRemoveExercise: () -> Void
    var onRemoveSets: (IndexSet) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            TextField("Exercise name", text: $exercise.name)
                .font(MarbleTypography.rowTitle)
                .onChange(of: exercise.name) { _, _ in onNameChanged() }
                .accessibilityIdentifier("TextEntry.Exercise.Name")

            matchRow

            ForEach($exercise.sets) { $set in
                TextEntrySetRow(set: $set, metrics: exercise.metricsProfile)
            }
            .onDelete(perform: onRemoveSets)

            Button(action: onAddSet) {
                Label("Add set", systemImage: "plus")
                    .font(MarbleTypography.rowMeta)
            }
            .accessibilityIdentifier("TextEntry.Exercise.AddSet")
        } header: {
            HStack {
                SectionHeaderView(title: "Exercise")
                Spacer()
                Button(role: .destructive, action: onRemoveExercise) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(MarbleTypography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityIdentifier("TextEntry.Exercise.Remove")
            }
        }
    }

    /// Shows how this exercise lands in the library — reuse an existing row or
    /// create a new one — with a menu to change the decision.
    @ViewBuilder
    private var matchRow: some View {
        if let resolution {
            Menu {
                ForEach(resolution.suggestions, id: \.candidate.id) { match in
                    Button {
                        onChoose(.library(id: match.candidate.id, name: match.candidate.name))
                    } label: {
                        if case let .library(id, _) = resolution.choice, id == match.candidate.id {
                            Label(match.candidate.name, systemImage: "checkmark")
                        } else {
                            Text(match.candidate.name)
                        }
                    }
                }
                Button {
                    onChoose(.createNew)
                } label: {
                    if resolution.choice == .createNew {
                        Label(createLabel, systemImage: "checkmark")
                    } else {
                        Text(createLabel)
                    }
                }
            } label: {
                HStack(spacing: MarbleSpacing.xs) {
                    Image(systemName: matchIcon)
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchTitle)
                            .font(MarbleTypography.rowMeta)
                        if resolution.autoConfidence == .likely {
                            Text("Close match — double-check")
                                .font(MarbleTypography.caption)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("TextEntry.Exercise.Match")
        }
    }

    private var createLabel: String {
        let name = exercise.trimmedName
        return name.isEmpty ? "Create new exercise" : "Create new \"\(name)\""
    }

    private var matchTitle: String {
        switch resolution?.choice {
        case let .library(_, name):
            return "Logs to \(name)"
        case .createNew, nil:
            return "New exercise in your library"
        }
    }

    private var matchIcon: String {
        switch resolution?.choice {
        case .library:
            return "checkmark.circle"
        case .createNew, nil:
            return "plus.circle"
        }
    }
}

// MARK: - Set row

private struct TextEntrySetRow: View {
    @Binding var set: ParsedSetDraft
    let metrics: ExerciseMetricsProfile

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            if metrics.usesWeight {
                HStack {
                    OptionalNumberField(
                        title: "Weight",
                        formatter: Formatters.weight,
                        value: $set.weight,
                        accessibilityIdentifier: "TextEntry.Set.Weight"
                    )
                    Picker("Unit", selection: $set.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("TextEntry.Set.WeightUnit")
                }
            }

            if metrics.usesReps {
                OptionalIntegerField(
                    title: "Reps",
                    value: $set.reps,
                    accessibilityIdentifier: "TextEntry.Set.Reps"
                )
            }

            if metrics.usesDistance {
                HStack {
                    OptionalNumberField(
                        title: "Distance",
                        formatter: Formatters.distance,
                        value: $set.distance,
                        accessibilityIdentifier: "TextEntry.Set.Distance"
                    )
                    Picker("Unit", selection: $set.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.symbol.uppercased()).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("TextEntry.Set.DistanceUnit")
                }
            }

            if metrics.usesDuration {
                HStack {
                    Text("Duration")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Spacer()
                    DurationPicker(durationSeconds: $set.durationSeconds)
                        .accessibilityIdentifier("TextEntry.Set.Duration")
                }
            }

            OptionalIntegerField(
                title: "Rest (sec)",
                value: $set.restSeconds,
                accessibilityIdentifier: "TextEntry.Set.Rest"
            )
        }
        .padding(.vertical, MarbleSpacing.xs)
    }
}
