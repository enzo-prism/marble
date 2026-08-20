import Combine
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The end-to-end "type or paste a workout" flow: free text → on-device parse →
/// review matches/edit → add to journal. Presented as a sheet from the import
/// screen; the review step is the scan flow's reviewer plus per-exercise library
/// matching, so the user approves exactly which rows are reused or created.
struct WorkoutTextEntryView: View {
    @State private var viewModel: WorkoutTextEntryViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var textFocused: Bool
    @State private var showingDiscardDialog = false
    /// Whether the clipboard holds text worth offering a Paste button for.
    /// `hasStrings` reads no content, so it never trips the paste-permission
    /// prompt; refreshed when the sheet appears and when the app foregrounds.
    @State private var clipboardHasText = false
    @State private var showingFileImporter = false

    init(initialText: String = "") {
        _viewModel = State(wrappedValue: WorkoutTextEntryViewModel(initialText: initialText))
    }

    /// Test seam so unit-driven previews aren't required to go through `init(initialText:)`.
    init(viewModel: WorkoutTextEntryViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.backgroundColor(for: colorScheme))
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar { toolbarContent }
        }
        // HIG sheet-dismissal protection: a swipe-down must not silently throw
        // away typed text or a reviewed draft; the imported phase stays freely
        // dismissible.
        .interactiveDismissDisabled(hasUnsavedEdits)
        .confirmationDialog(
            "Discard this import?",
            isPresented: $showingDiscardDialog,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        // Load the on-device model while the user is still typing, so the first
        // parse doesn't pay model-load latency inside the processing spinner.
        .task { FoundationModelsWorkoutScanParser.prewarm() }
        .task { clipboardHasText = UIPasteboard.general.hasStrings }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            clipboardHasText = UIPasteboard.general.hasStrings
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .json],
            allowsMultipleSelection: true
        ) { result in
            ingestFiles(result)
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .input: inputView
        case .processing: processingView
        case .batchReview:
            WorkoutTextBatchReview(
                viewModel: viewModel,
                onReview: { viewModel.openSession($0) },
                onImport: { viewModel.commitSelected(into: modelContext) }
            )
        case .review: reviewView
        case .imported: importedView
        }
    }

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                Text("Paste a workout, a week of notes, or a Hevy/Strong export. Marble reads it on your device, splits it into workouts, and matches your exercise library before anything is logged.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("TextEntry.Input")

                // System PasteButton: one tap moves a copied workout (Hevy,
                // Strong, Notes) into the editor with no clipboard-permission
                // prompt and no programmatic clipboard reads — the privacy
                // posture the feature promises.
                HStack {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Choose File", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("TextEntry.ChooseFile")
                    Spacer()
                    if clipboardHasText {
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            viewModel.ingestPastedText(pasted)
                        }
                        .labelStyle(.titleAndIcon)
                        .tint(Theme.secondaryTextColor(for: colorScheme))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("TextEntry.Paste")
                    }
                }

                TextEditor(text: $viewModel.text)
                    .font(MarbleTypography.rowSubtitle)
                    .focused($textFocused)
                    .scrollContentBackground(.hidden)
                    .writingToolsBehavior(.disabled)
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
                    .onChange(of: viewModel.text) { _, _ in viewModel.updateLivePreview() }
                    .dropDestination(for: String.self) { items, _ in
                        guard let pasted = items.first else { return false }
                        viewModel.ingestPastedText(pasted)
                        return true
                    }

                if let preview = viewModel.livePreview {
                    livePreviewView(preview)
                }

                Button {
                    textFocused = false
                    Task { await viewModel.preview(in: modelContext) }
                } label: {
                    Text(previewButtonTitle)
                }
                .buttonStyle(MarbleActionButtonStyle(
                    isEnabledOverride: !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    expandsHorizontally: true,
                    prominence: .primary
                ))
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("TextEntry.Preview")

                Label(
                    viewModel.privacyCaption,
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
    }

    private var previewButtonTitle: String {
        if let preview = viewModel.livePreview, preview.sessionCount > 1 {
            return "Preview Workouts"
        }
        return "Preview Workout"
    }

    /// Eased display value for the processing bar. Real parse stages anchor it;
    /// the timer eases toward the current anchor so the bar keeps moving during
    /// a long on-device model pass without ever crossing into the next stage.
    @State private var processingProgress: Double = 0
    private let processingTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    /// Fraction each parse stage anchors the progress bar to. Exact percentages
    /// are unknowable (the model exposes no token count), so the anchors split
    /// the pipeline where the time actually goes: the two model readings.
    private var processingTarget: Double {
        if let batch = viewModel.batchProgress, batch.total > 1 {
            return min(0.95, Double(batch.current) / Double(batch.total))
        }
        switch viewModel.parseStage {
        case .readingNotation: return 0.18
        case .interpreting(let pass, _): return pass <= 1 ? 0.52 : 0.8
        case .finalizing: return 0.95
        }
    }

    private var processingStageLabel: String {
        if let batch = viewModel.batchProgress, batch.total > 1 {
            return "Reading workout \(batch.current) of \(batch.total)…"
        }
        switch viewModel.parseStage {
        case .readingNotation: return "Reading your text…"
        case .interpreting: return "Interpreting with Apple Intelligence…"
        case .finalizing: return "Matching your exercise library…"
        }
    }

    private var processingView: some View {
        VStack(spacing: MarbleSpacing.s) {
            ProgressView(value: processingProgress)
                .tint(Theme.primaryTextColor(for: colorScheme))
            HStack {
                Text(processingStageLabel)
                Spacer()
                Text("\(Int((processingProgress * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .accessibilityIdentifier("TextEntry.Processing")
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { processingProgress = 0.03 }
        .onReceive(processingTimer) { _ in
            guard viewModel.phase == .processing else { return }
            processingProgress += (processingTarget - processingProgress) * 0.045
        }
    }

    /// Per-line feedback under the editor, recomputed per keystroke by the
    /// deterministic parser: recognized exercises read as a confirmation, and
    /// unrecognized lines are flagged while fixing them is cheapest — before
    /// Preview, not after.
    @ViewBuilder
    private func livePreviewView(_ preview: WorkoutTextEntryViewModel.LivePreview) -> some View {
        if !preview.recognized.isEmpty || !preview.unrecognized.isEmpty || preview.sessionCount > 1 {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                if preview.sessionCount > 1 {
                    Label(
                        "Looks like \(preview.sessionCount) workouts · \(preview.totalSets) sets",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("TextEntry.LivePreview")
                    ForEach(Array(preview.recognized.prefix(8))) { line in
                        Text("\(line.name) · \(line.setCount) set\(line.setCount == 1 ? "" : "s")")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                } else {
                    ForEach(preview.recognized) { line in
                        Label(
                            "\(line.name) · \(line.setCount) set\(line.setCount == 1 ? "" : "s")",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    ForEach(Array(preview.unrecognized.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "exclamationmark.circle")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    if !preview.unrecognized.isEmpty {
                        Text("\(preview.unrecognized.count) line\(preview.unrecognized.count == 1 ? "" : "s") not recognized yet — try \"Name 3x8 @ 185\".")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.8))
                    }
                }
            }
        }
    }

    private var reviewView: some View {
        List {
            Section {
                TextField("Workout title", text: $viewModel.draft.title)
                    .font(MarbleTypography.rowTitle)
                    .accessibilityIdentifier("TextEntry.Title")
            } header: {
                SectionHeaderView(title: "Workout")
            }

            ImportDateSection(idPrefix: "TextEntry", performedAt: $viewModel.draft.performedAt)

            if viewModel.alreadyImported {
                Section {
                    Label("This workout is already in your journal. Importing again will skip it.", systemImage: "exclamationmark.triangle")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.AlreadyImported")
                }
            }

            if !viewModel.unparsedLines.isEmpty {
                Section {
                    ForEach(Array(viewModel.unparsedLines.enumerated()), id: \.offset) { index, line in
                        UnparsedLineRow(text: line, index: index) { edited in
                            Task { await viewModel.retryUnparsedLine(at: index, replacement: edited) }
                        }
                    }
                } header: {
                    SectionHeaderView(title: "Couldn't read \(viewModel.unparsedLines.count) line\(viewModel.unparsedLines.count == 1 ? "" : "s")")
                } footer: {
                    Text("Edit a line into standard notation (like \"Bench 3x8 @ 185\") and it joins the workout above.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }

            ForEach($viewModel.draft.exercises) { $exercise in
                TextEntryExerciseSection(
                    exercise: $exercise,
                    workoutDate: viewModel.draft.performedAt,
                    resolution: viewModel.resolution(for: exercise.id),
                    onChoose: { choice in viewModel.choose(choice, for: exercise.id) },
                    onNameChanged: { viewModel.refreshResolution(forExerciseWithID: exercise.id) },
                    onAddSet: { viewModel.addSet(toExerciseWithID: exercise.id) },
                    onRemoveExercise: { viewModel.removeExercise(withID: exercise.id) },
                    onRemoveSets: { offsets in viewModel.removeSets(fromExerciseWithID: exercise.id, at: offsets) },
                    canMoveUp: viewModel.exerciseIndex(withID: exercise.id).map { $0 > 0 } ?? false,
                    canMoveDown: viewModel.exerciseIndex(withID: exercise.id).map { $0 < viewModel.draft.exercises.count - 1 } ?? false,
                    onMove: { delta in viewModel.moveExercise(withID: exercise.id, by: delta) }
                )
            }

            Section {
                Button {
                    viewModel.addExercise()
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("TextEntry.AddExercise")
            } footer: {
                // Footer, not an inline row: it annotates the section rather
                // than being content the user acts on.
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
            if !viewModel.isDrillingInFromBatch {
                importButton
            }
        }
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
                Text(importedHeadline(summary))
                    .font(MarbleTypography.emptyTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("TextEntry.Imported")
                if let volume = viewModel.celebration.volumeText {
                    Text("\(volume) total volume")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.ImportedVolume")
                }
                if !viewModel.celebration.prExercises.isEmpty {
                    Label(
                        "New PR\(viewModel.celebration.prExercises.count == 1 ? "" : "s"): \(viewModel.celebration.prExercises.joined(separator: ", "))",
                        systemImage: "trophy.fill"
                    )
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("TextEntry.ImportedPRs")
                }
                if summary.createdExercises > 0 {
                    Text("\(summary.createdExercises) new exercise\(summary.createdExercises == 1 ? "" : "s") added to your library.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                if summary.skipped > 0 {
                    Text(summary.importedWorkouts == 0
                         ? "Already in your journal."
                         : "Skipped \(summary.skipped) already imported.")
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
    }

    private func importedHeadline(_ summary: WorkoutImporter.Summary) -> String {
        if summary.importedWorkouts > 1 {
            return "Added \(summary.importedWorkouts) workouts"
        }
        if summary.importedSets > 0 {
            return "Added \(summary.importedSets) set\(summary.importedSets == 1 ? "" : "s")"
        }
        return "Nothing new to import"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(leadingToolbarTitle) {
                if viewModel.isDrillingInFromBatch {
                    viewModel.returnToBatch()
                } else if viewModel.phase == .batchReview {
                    viewModel.editText()
                } else if hasUnsavedEdits {
                    showingDiscardDialog = true
                } else {
                    dismiss()
                }
            }
            .accessibilityIdentifier("TextEntry.Dismiss")
        }
        if viewModel.phase == .review {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Text") { viewModel.editText() }
                    .accessibilityIdentifier("TextEntry.EditText")
            }
        }
        if viewModel.phase == .batchReview {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.allImportableSelected ? "Deselect All" : "Select All") {
                    viewModel.toggleSelectAllImportable()
                }
                .disabled(!viewModel.canToggleBatchSelection)
                .accessibilityIdentifier("TextEntry.Batch.SelectAll")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Text") { viewModel.editText() }
                    .accessibilityIdentifier("TextEntry.EditText")
            }
        }
    }

    private var leadingToolbarTitle: String {
        if viewModel.isDrillingInFromBatch { return "Workouts" }
        switch viewModel.phase {
        case .review, .batchReview: return "Cancel"
        default: return "Done"
        }
    }

    /// Unsaved work worth protecting from an accidental dismissal: typed text
    /// (kept through the processing step) or a reviewed draft with importable
    /// sets. The imported phase never blocks — the work is already saved.
    private var hasUnsavedEdits: Bool {
        switch viewModel.phase {
        case .input, .processing:
            return !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .review:
            return viewModel.draft.hasContent
        case .batchReview:
            return viewModel.sessions.contains { $0.draft.hasContent }
        case .imported:
            return false
        }
    }

    private var navigationTitle: String {
        switch viewModel.phase {
        case .batchReview: return "Review Workouts"
        case .review: return viewModel.isDrillingInFromBatch ? viewModel.draft.title : "Type a Workout"
        case .imported: return "Imported"
        default: return "Paste or Type"
        }
    }

    private func ingestFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            viewModel.errorMessage = "Couldn't open that file. Try a .txt, .csv, or .json export."
        case .success(let urls):
            var parts: [String] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else { continue }
                if let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { parts.append(trimmed) }
                }
            }
            guard !parts.isEmpty else {
                viewModel.errorMessage = "That file didn't contain any text."
                return
            }
            viewModel.ingestSources(parts)
        }
    }
}

// MARK: - Unparsed line row

/// One "couldn't read" line in review: the raw text, editable in place. Submitting
/// hands the edited text back to the parser; a line that now parses joins the
/// draft, one that still doesn't stays listed with the new text.
private struct UnparsedLineRow: View {
    let text: String
    let index: Int
    var onSubmit: (String) -> Void

    @State private var editedText: String
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, index: Int, onSubmit: @escaping (String) -> Void) {
        self.text = text
        self.index = index
        self.onSubmit = onSubmit
        _editedText = State(initialValue: text)
    }

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            TextField("Line notation", text: $editedText)
                .font(MarbleTypography.rowSubtitle)
                .onSubmit { onSubmit(editedText) }
                .submitLabel(.done)
                .accessibilityIdentifier("TextEntry.Unparsed.Line.\(index)")
        }
    }
}

// MARK: - Exercise section

private struct TextEntryExerciseSection: View {
    @Binding var exercise: ParsedExerciseDraft
    /// The workout-level date, seeding any per-set date & time override.
    let workoutDate: Date?
    let resolution: WorkoutTextEntryViewModel.Resolution?
    var onChoose: (WorkoutTextEntryViewModel.Resolution.Choice) -> Void
    var onNameChanged: () -> Void
    var onAddSet: () -> Void
    var onRemoveExercise: () -> Void
    var onRemoveSets: (IndexSet) -> Void
    /// Reorder affordances: review order is the order the workout saves in, so
    /// a paste that listed exercises out of order is fixable here. Button-based
    /// because the list renders one Section per exercise and SwiftUI move
    /// handles only work within a single section.
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onMove: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            TextField("Exercise name", text: $exercise.name)
                .font(MarbleTypography.rowTitle)
                .onChange(of: exercise.name) { _, _ in onNameChanged() }
                .accessibilityIdentifier("TextEntry.Exercise.Name.\(exercise.id.uuidString)")

            matchRow

            // No `.onDelete`: `ImportSetTimingRows` attaches `.swipeActions`,
            // which suppresses the synthesized Delete, so it re-adds an
            // explicit destructive Delete wired to the same removal closure.
            ForEach($exercise.sets) { $set in
                ImportSetTimingRows(
                    idPrefix: "TextEntry",
                    set: $set,
                    workoutDate: workoutDate,
                    onDelete: {
                        if let index = exercise.sets.firstIndex(where: { $0.id == set.id }) {
                            onRemoveSets(IndexSet(integer: index))
                        }
                    }
                ) {
                    TextEntrySetRow(set: $set, metrics: exercise.metricsProfile)
                }
            }

            Button(action: onAddSet) {
                Label("Add set", systemImage: "plus")
                    .font(MarbleTypography.rowMeta)
            }
            .accessibilityIdentifier("TextEntry.Exercise.AddSet.\(exercise.id.uuidString)")
        } header: {
            HStack(spacing: MarbleSpacing.s) {
                SectionHeaderView(title: "Exercise")
                Spacer()
                Button { onMove(-1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .disabled(!canMoveUp)
                .opacity(canMoveUp ? 1 : 0.3)
                .accessibilityLabel("Move exercise up")
                .accessibilityIdentifier("TextEntry.Exercise.MoveUp.\(exercise.id.uuidString)")
                Button { onMove(1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .disabled(!canMoveDown)
                .opacity(canMoveDown ? 1 : 0.3)
                .accessibilityLabel("Move exercise down")
                .accessibilityIdentifier("TextEntry.Exercise.MoveDown.\(exercise.id.uuidString)")
                Button(role: .destructive, action: onRemoveExercise) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(MarbleTypography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityIdentifier("TextEntry.Exercise.Remove.\(exercise.id.uuidString)")
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
            .accessibilityIdentifier("TextEntry.Exercise.Match.\(exercise.id.uuidString)")
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
                        accessibilityIdentifier: "TextEntry.Set.Weight.\(set.id.uuidString)"
                    )
                    Picker("Unit", selection: $set.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("TextEntry.Set.WeightUnit.\(set.id.uuidString)")
                }
            }

            if metrics.usesReps {
                OptionalIntegerField(
                    title: "Reps",
                    value: $set.reps,
                    accessibilityIdentifier: "TextEntry.Set.Reps.\(set.id.uuidString)"
                )
            }

            if metrics.usesDistance {
                HStack {
                    OptionalNumberField(
                        title: "Distance",
                        formatter: Formatters.distance,
                        value: $set.distance,
                        accessibilityIdentifier: "TextEntry.Set.Distance.\(set.id.uuidString)"
                    )
                    Picker("Unit", selection: $set.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.symbol.uppercased()).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("TextEntry.Set.DistanceUnit.\(set.id.uuidString)")
                }
            }

            if metrics.usesDuration {
                HStack {
                    Text("Duration")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Spacer()
                    DurationPicker(durationSeconds: $set.durationSeconds)
                        .accessibilityIdentifier("TextEntry.Set.Duration.\(set.id.uuidString)")
                }
            }

            OptionalIntegerField(
                title: "Rest (sec)",
                value: $set.restSeconds,
                accessibilityIdentifier: "TextEntry.Set.Rest.\(set.id.uuidString)"
            )
        }
        .padding(.vertical, MarbleSpacing.xs)
    }
}
