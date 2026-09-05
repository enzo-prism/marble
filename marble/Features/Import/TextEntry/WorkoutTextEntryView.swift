import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Where the text-entry flow lives. The primary tab keeps a draft alive across
/// tab switches; the sheet mode preserves the scan/import handoff experience.
enum WorkoutTextEntryPresentation: Equatable {
    case sheet
    case primaryTab
}

/// The end-to-end "type or paste a workout" flow: free text → on-device parse →
/// review matches/edit → add to journal. The review step is the scan flow's
/// reviewer plus per-exercise library matching, so the user approves exactly
/// which rows are reused or created.
struct WorkoutTextEntryView: View {
    @State private var viewModel: WorkoutTextEntryViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var textFocused: Bool
    @State private var showingDiscardDialog = false
    /// Whether the clipboard holds text worth offering a Paste button for.
    /// `hasStrings` reads no content, so it never trips the paste-permission
    /// prompt; refreshed when the sheet appears and when the app foregrounds.
    @State private var clipboardHasText = false
    @State private var showingFileImporter = false
    @State private var showingPlan = false
    @State private var showingSettings = false
    @State private var showingIncomingTextChoice = false
    @State private var pendingIncomingText: String?
    @State private var pendingReviewDraft: ParsedWorkoutDraft?
    @State private var showingIncomingReviewChoice = false
    @State private var showingSavedSheetDraft = false
    @State private var hasSavedSheetDraft = false
    private let autoPreviewOnAppear: Bool
    private let presentation: WorkoutTextEntryPresentation
    private let onShowJournal: (() -> Void)?
    private let onShowWorkout: (() -> Void)?
    private let prewarmsModel: Bool
    @State private var didAutoPreview = false
    @State private var didPrewarmModel = false

    init(
        initialText: String = "",
        autoPreview: Bool? = nil,
        presentation: WorkoutTextEntryPresentation = .sheet,
        onShowJournal: (() -> Void)? = nil,
        onShowWorkout: (() -> Void)? = nil,
        prewarmsModel: Bool = true,
        draftStore: (any WorkoutEntryDraftStoring)? = nil
    ) {
        let trimmed = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = draftStore ?? WorkoutEntryDraftStore.applicationStore(
            slot: presentation == .primaryTab ? "primary" : "sheet"
        )
        let model = WorkoutTextEntryViewModel(initialText: initialText, draftStore: store)
        _viewModel = State(wrappedValue: model)
        _pendingIncomingText = State(initialValue: (model.hasRestoredDraft || model.hasUnreadableSavedDraft) && !trimmed.isEmpty ? initialText : nil)
        self.autoPreviewOnAppear = autoPreview ?? !trimmed.isEmpty
        self.presentation = presentation
        self.onShowJournal = onShowJournal
        self.onShowWorkout = onShowWorkout
        self.prewarmsModel = prewarmsModel
    }

    init(initialReviewDraft: ParsedWorkoutDraft, draftStore: (any WorkoutEntryDraftStoring)? = nil) {
        let model = WorkoutTextEntryViewModel(draftStore: draftStore ?? WorkoutEntryDraftStore.applicationStore(slot: "sheet"))
        self.init(viewModel: model)
        // View values can be reconstructed after commit. Only the retained
        // model's appearance lifecycle may create a new persistent draft.
        _pendingReviewDraft = State(initialValue: initialReviewDraft)
    }

    /// Test seam so unit-driven previews aren't required to go through `init(initialText:)`.
    init(
        viewModel: WorkoutTextEntryViewModel,
        presentation: WorkoutTextEntryPresentation = .sheet,
        onShowJournal: (() -> Void)? = nil,
        onShowWorkout: (() -> Void)? = nil,
        prewarmsModel: Bool = true
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.autoPreviewOnAppear = false
        self.presentation = presentation
        self.onShowJournal = onShowJournal
        self.onShowWorkout = onShowWorkout
        self.prewarmsModel = prewarmsModel
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.backgroundColor(for: colorScheme))
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .top) {
                    if presentation == .primaryTab && hasSavedSheetDraft {
                        Button("Resume Saved Import", systemImage: "square.and.pencil") {
                            showingSavedSheetDraft = true
                        }
                        .buttonStyle(MarbleActionButtonStyle())
                        .accessibilityIdentifier("WorkoutEntry.Draft.ResumeSheet")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Theme.backgroundColor(for: colorScheme))
                    }
                    if let message = viewModel.draftStorageMessage {
                        VStack(alignment: .leading) {
                            Text(message).font(.callout)
                            Button(viewModel.hasUnreadableSavedDraft ? "Try Opening Again" : "Try Saving Again") {
                                if viewModel.hasUnreadableSavedDraft { viewModel.retryOpeningDraft() }
                                else { viewModel.saveDraftNow() }
                            }
                                .buttonStyle(MarbleActionButtonStyle())
                                .accessibilityIdentifier("WorkoutEntry.Draft.Retry")
                        }
                        .padding()
                        .background(Theme.backgroundColor(for: colorScheme))
                    }
                }
        }
        // HIG sheet-dismissal protection: a swipe-down must not silently throw
        // away typed text or a reviewed draft; the imported phase stays freely
        // dismissible.
        .interactiveDismissDisabled(presentation == .sheet && hasUnsavedEdits)
        .confirmationDialog(
            "Discard this import?",
            isPresented: $showingDiscardDialog,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { discardCurrentDraft() }
                .accessibilityIdentifier("WorkoutEntry.Draft.ConfirmDiscard")
            if presentation == .sheet && !viewModel.hasUnreadableSavedDraft {
                Button("Save Draft & Close") {
                    if viewModel.saveDraftNow() { dismiss() }
                }
                .accessibilityIdentifier("WorkoutEntry.Draft.SaveAndClose")
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog(
            "Use the workout you selected?",
            isPresented: $showingIncomingReviewChoice,
            titleVisibility: .visible
        ) {
            Button("Replace with Selected Workout", role: .destructive) {
                guard let incoming = pendingReviewDraft else { return }
                pendingReviewDraft = nil
                viewModel.startReview(with: incoming)
            }
            .accessibilityIdentifier("WorkoutEntry.Incoming.Repeat")
            Button("Keep Saved Draft", role: .cancel) { pendingReviewDraft = nil }
                .accessibilityIdentifier("WorkoutEntry.Incoming.KeepSaved")
        }
        .confirmationDialog(
            "You already have a workout draft",
            isPresented: $showingIncomingTextChoice,
            titleVisibility: .visible
        ) {
            if viewModel.phase == .input {
                Button("Add to Current Draft") { applyIncomingText(replacing: false) }
                    .accessibilityIdentifier("WorkoutEntry.Incoming.Append")
            }
            Button("Replace Current Draft", role: .destructive) { applyIncomingText(replacing: true) }
                .accessibilityIdentifier("WorkoutEntry.Incoming.Replace")
            Button("Keep Current Draft", role: .cancel) { pendingIncomingText = nil }
                .accessibilityIdentifier("WorkoutEntry.Incoming.Keep")
        } message: {
            Text("Choose how to handle the workout sent to Marble.")
        }
        // Apple's Foundation Models guidance reserves prewarming for a strong
        // near-term signal. The first typed character while the editor is
        // focused is that signal; merely launching the default tab is not.
        .task(id: textFocused && !viewModel.text.isEmpty) {
            guard prewarmsModel,
                  textFocused,
                  !viewModel.text.isEmpty,
                  !didPrewarmModel else { return }
            didPrewarmModel = true
            FoundationModelsWorkoutScanParser.prewarm()
        }
        .task { clipboardHasText = UIPasteboard.general.hasStrings }
        .task {
            if let incoming = pendingReviewDraft,
               viewModel.prepareInitialReview(incoming, in: modelContext) {
                pendingReviewDraft = nil
            }
        }
        .task {
            guard autoPreviewOnAppear, !didAutoPreview, !viewModel.hasRestoredDraft, !viewModel.hasUnreadableSavedDraft else { return }
            didAutoPreview = true
            await viewModel.preview(in: modelContext)
        }
        .task {
            refreshSavedSheetDraft()
            consumePendingTextImportIfNeeded()
        }
        .onChange(of: viewModel.hasRestoredDraft) { wasRestored, isRestored in
            if wasRestored && !isRestored && pendingIncomingText != nil {
                showingIncomingTextChoice = true
            } else if wasRestored && !isRestored && pendingReviewDraft != nil {
                showingIncomingReviewChoice = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marbleOpenTextImport)) { _ in
            consumePendingTextImportIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            clipboardHasText = UIPasteboard.general.hasStrings
            refreshSavedSheetDraft()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.saveDraftNow() }
        }
        .onDisappear { viewModel.saveDraftNow() }
        .sheet(isPresented: $showingSavedSheetDraft, onDismiss: refreshSavedSheetDraft) {
            WorkoutTextEntryView(presentation: .sheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            ingestFiles(result)
        }
        .sheet(isPresented: $showingPlan) {
            SplitView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        if viewModel.hasRestoredDraft || viewModel.hasUnreadableSavedDraft {
            ScrollView {
                VStack(spacing: MarbleSpacing.l) {
                    Image(systemName: "square.and.pencil").font(.largeTitle).accessibilityHidden(true)
                    Text(viewModel.hasUnreadableSavedDraft ? "Your draft needs attention" : "Your workout draft is ready").font(.title2)
                    Text(viewModel.hasUnreadableSavedDraft ? "Try opening your saved draft again, or discard it to start a new workout." : "Your edits and exercise matches are saved. Pick up where you left off.")
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Button("Resume Workout") { viewModel.resumeDraft(in: modelContext) }
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                        .disabled(viewModel.hasUnreadableSavedDraft)
                        .accessibilityIdentifier("WorkoutEntry.Draft.Resume")
                    Button("Discard Draft", role: .destructive) { showingDiscardDialog = true }
                        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
                        .accessibilityIdentifier("WorkoutEntry.Draft.Discard")
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .padding(MarbleSpacing.l)
                .frame(maxWidth: .infinity)
            }
        } else {
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
    }

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    Label(
                        viewModel.usesOnDeviceModel ? "Apple Intelligence" : "On-device parsing",
                        systemImage: viewModel.usesOnDeviceModel ? "apple.intelligence" : "iphone"
                    )
                    .font(MarbleTypography.smallLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("WorkoutEntry.IntelligenceStatus")

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                            inputTitle
                            Spacer(minLength: MarbleSpacing.s)
                            if !viewModel.text.isEmpty {
                                clearWorkoutButton
                            }
                        }

                        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                            inputTitle
                            if !viewModel.text.isEmpty {
                                clearWorkoutButton
                            }
                        }
                    }
                }

                // The editor is the primary task, so it precedes explanatory
                // copy and import shortcuts. This keeps it reachable on the
                // first screen even at Accessibility XXXL.
                TextEditor(text: $viewModel.text)
                    .font(MarbleTypography.rowSubtitle)
                    .focused($textFocused)
                    .marbleKeyboardToolbar(doneIdentifier: "TextEntry.Keyboard.Done")
                    .scrollContentBackground(.hidden)
                    .writingToolsBehavior(.disabled)
                    .padding(MarbleSpacing.s)
                    .frame(minHeight: editorMinimumHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.chipFillColor(for: colorScheme))
                    )
                    .overlay(alignment: .topLeading) {
                        if viewModel.text.isEmpty {
                            Text("Bench press 3x8 @ 185 lb\nIncline press 3x10 @ 60 lb\nPlank 3x45 seconds")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .padding(MarbleSpacing.s)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("TextEntry.Editor")
                    .accessibilityLabel("Workout text")
                    .accessibilityHint("Type or paste a workout in plain language or common workout notation.")
                    .task(id: viewModel.text) {
                        await viewModel.updateLivePreview(for: viewModel.text)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let pasted = items.first else { return false }
                        viewModel.ingestPastedText(pasted)
                        return true
                    }

                Text("Write it naturally. Marble turns your words into structured sets for you to review before saving.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

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
                    .tint(Theme.primaryTextColor(for: colorScheme))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("TextEntry.ChooseFile")
                    Spacer()
                    if clipboardHasText {
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            viewModel.ingestPastedText(pasted)
                        }
                        .labelStyle(.titleAndIcon)
                        .tint(Theme.primaryTextColor(for: colorScheme))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("TextEntry.Paste")
                    }
                }

                if viewModel.text.isEmpty {
                    Menu {
                        Button("Strength workout") {
                            viewModel.startNewWorkout(with: "Bench press 3 sets of 8 at 185 lb, resting 90 seconds\nIncline dumbbell press 3x10 @ 60 lb\nPlank 3x45 seconds")
                        }
                        .accessibilityIdentifier("WorkoutEntry.Example.Strength")
                        Button("Run") {
                            viewModel.startNewWorkout(with: "Easy run today: 5 kilometers in 28 minutes")
                        }
                        .accessibilityIdentifier("WorkoutEntry.Example.Run")
                        Button("Multiple days") {
                            viewModel.startNewWorkout(with: "Monday — Push\nBench 3x8 @ 185 lb\nCable fly 3x12\n\nWednesday — Pull\nDeadlift 3x5 @ 225 lb\nPull ups 3x8")
                        }
                        .accessibilityIdentifier("WorkoutEntry.Example.Multiple")
                    } label: {
                        Label("Try an example", systemImage: "text.quote")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.primaryTextColor(for: colorScheme))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("WorkoutEntry.Examples")
                }

                if let preview = viewModel.livePreview {
                    livePreviewView(preview)
                }

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
            .frame(maxWidth: MarbleLayout.formMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("WorkoutEntry.Root")
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            reviewButton
        }
    }

    private var reviewButton: some View {
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
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.vertical, MarbleSpacing.s)
        .frame(maxWidth: MarbleLayout.formMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("TextEntry.Preview")
    }

    private var inputTitle: some View {
        Text("Paste or type your workout")
            .font(MarbleTypography.emptyTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
    }

    private var clearWorkoutButton: some View {
        Button {
            viewModel.reset()
        } label: {
            Label("Clear", systemImage: "xmark.circle.fill")
        }
        .font(MarbleTypography.button)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .frame(minHeight: 44)
        .accessibilityIdentifier("TextEntry.Clear")
        .accessibilityHint("Removes all text from the workout editor.")
    }

    private var editorMinimumHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return presentation == .primaryTab ? 380 : 300
        }
        return presentation == .primaryTab ? 280 : 200
    }

    private var previewButtonTitle: String {
        if let preview = viewModel.livePreview, preview.sessionCount > 1 {
            return "Review Workouts"
        }
        return "Review Workout"
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
            ProgressView()
                .tint(Theme.primaryTextColor(for: colorScheme))
            Text(processingStageLabel)
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(processingStageLabel)
        .accessibilityIdentifier("TextEntry.Processing")
    }

    /// Per-line feedback under the editor, recomputed after a short typing
    /// pause: recognized exercises read as a confirmation, and
    /// unrecognized lines are flagged while fixing them is cheapest — before
    /// Preview, not after.
    @ViewBuilder
    private func livePreviewView(_ preview: WorkoutTextEntryViewModel.LivePreview) -> some View {
        if !preview.recognized.isEmpty || !preview.unrecognized.isEmpty || preview.sessionCount > 1 {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                if preview.sessionCount > 1 {
                    Label(
                        "Looks like \(preview.sessionCount) workouts · \(preview.totalSets) sets",
                        systemImage: preview.unrecognized.isEmpty
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("TextEntry.LivePreview")
                    ForEach(Array(preview.recognized.prefix(8))) { line in
                        Text("\(line.name) · \(line.setCount) set\(line.setCount == 1 ? "" : "s")")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    ForEach(Array(preview.unrecognized.prefix(4).enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "exclamationmark.circle")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                    if !preview.unrecognized.isEmpty {
                        Text("\(preview.unrecognized.count) line\(preview.unrecognized.count == 1 ? "" : "s") need review before this batch can be added.")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.8))
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
                        Text("\(preview.unrecognized.count) line\(preview.unrecognized.count == 1 ? "" : "s") not organized yet. Review to check every detail.")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.8))
                    }
                }
            }
        }
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text(reviewSummary)
                        .font(MarbleTypography.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("TextEntry.ReviewSummary")
                    ForEach(viewModel.draft.importableExercises) { exercise in
                        Text(exerciseReviewSummary(exercise))
                            .font(MarbleTypography.rowMeta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    WorkoutReviewSectionHeader(title: "Your workout")
                }

                if !viewModel.unparsedLines.isEmpty {
                    Section {
                        ForEach(viewModel.unparsedReviewLines) { line in
                            UnparsedLineRow(text: line.text, index: line.index, onSubmit: { edited in
                                Task { await viewModel.retryUnparsedLine(id: line.id, replacement: edited) }
                            }, onKeepNote: { edited in
                                viewModel.keepUnparsedLineAsNote(id: line.id, replacement: edited)
                            })
                        }
                    } header: {
                        WorkoutReviewSectionHeader(title: "Keep every detail")
                    } footer: {
                        Text("These lines need a closer look. Edit and retry, or keep them in workout notes before saving.")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }

                Section {
                    TextField("Workout title", text: $viewModel.draft.title)
                        .font(MarbleTypography.rowTitle)
                        .accessibilityIdentifier("TextEntry.Title")
                } header: {
                    WorkoutReviewSectionHeader(title: "Workout")
                }

                ImportDateSection(
                    idPrefix: "TextEntry",
                    performedAt: $viewModel.draft.performedAt,
                    notes: $viewModel.draft.notes,
                    durationSeconds: viewModel.draft.durationSeconds
                )

                if viewModel.alreadyImported {
                    Section {
                        Label("This workout is already in your journal. Importing again will skip it.", systemImage: "exclamationmark.triangle")
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("TextEntry.AlreadyImported")
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

                if !viewModel.reviewSourceText.isEmpty {
                    Section {
                        DisclosureGroup {
                            Text(viewModel.reviewSourceText)
                                .font(MarbleTypography.rowMeta)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("TextEntry.SourceText")
                        } label: {
                            Text("Original text")
                                .accessibilityIdentifier("TextEntry.SourceDisclosure")
                        }
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
            // Keep the first review heading clear of the navigation scroll edge.
            .contentMargins(.top, MarbleSpacing.s, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .clipped()
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
            isEnabledOverride: viewModel.canCommitWorkout,
            expandsHorizontally: true,
            prominence: .primary
        ))
        .disabled(!viewModel.canCommitWorkout)
        .accessibilityIdentifier("TextEntry.Import")
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.vertical, MarbleSpacing.s)
        .frame(maxWidth: MarbleLayout.formMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor(for: colorScheme))
    }

    private func exerciseReviewSummary(_ exercise: ParsedExerciseDraft) -> String {
        let count = exercise.sets.count
        let summary = "\(exercise.trimmedName) · \(count) set\(count == 1 ? "" : "s")"
        if exercise.sets.allSatisfy({ !$0.hasAnyValue }) {
            return summary + " · reps not specified"
        }
        if let first = exercise.sets.first, let distance = first.distance,
           exercise.sets.allSatisfy({ $0.distance == distance && $0.distanceUnit == first.distanceUnit }),
           let value = Formatters.distance.string(from: NSNumber(value: distance)) {
            return summary + " · \(value) \(first.distanceUnit.symbol) each"
        }
        return summary
    }

    private var reviewSummary: String {
        let exercises = viewModel.draft.importableExercises.count
        let sets = viewModel.draft.totalSetCount
        return "\(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }

    private var importButtonTitle: String {
        if !viewModel.unparsedLines.isEmpty { return "Review details" }
        let count = viewModel.draft.totalSetCount
        let destination = presentation == .primaryTab ? "Log" : "Journal"
        guard count > 0 else { return "Add to \(destination)" }
        return "Add \(count) set\(count == 1 ? "" : "s") to \(destination)"
    }

    private var importedView: some View {
        VStack(spacing: MarbleSpacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
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
            if presentation == .primaryTab {
                Button("View Log") { onShowJournal?() }
                    .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                    .accessibilityIdentifier("TextEntry.Imported.ViewLog")
                    .padding(.top, MarbleSpacing.s)

                Button("Add Another Workout") { viewModel.reset() }
                    .buttonStyle(MarbleActionButtonStyle(prominence: .standard))
                    .accessibilityIdentifier("TextEntry.Imported.AddAnother")
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                    .accessibilityIdentifier("TextEntry.ImportedDone")
                    .padding(.top, MarbleSpacing.s)
            }
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
        if presentation == .sheet {
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
        }

        if presentation == .primaryTab,
           !viewModel.hasRestoredDraft,
           !viewModel.hasUnreadableSavedDraft,
           viewModel.isDrillingInFromBatch {
            ToolbarItem(placement: .topBarLeading) {
                Button("Workouts") { viewModel.returnToBatch() }
                    .accessibilityIdentifier("TextEntry.Batch.Back")
            }
        }

        if presentation == .primaryTab,
           (viewModel.phase == .input || viewModel.phase == .imported) {
            if let onShowWorkout {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onShowWorkout) {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                    .accessibilityLabel("Start or open workout")
                    .accessibilityIdentifier("Workout.Open")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingPlan = true
                    } label: {
                        Label("Workout Plan", systemImage: "list.bullet.clipboard")
                    }
                    .accessibilityIdentifier("Workout.Plan")

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("Workout.Settings")
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("Workout.More")
            }

            LogSetToolbarItems()
        }

        if viewModel.phase == .review && !viewModel.hasRestoredDraft && !viewModel.hasUnreadableSavedDraft {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Text") { viewModel.editText() }
                    .accessibilityIdentifier("TextEntry.EditText")
            }
        }
        if viewModel.phase == .batchReview && !viewModel.hasRestoredDraft && !viewModel.hasUnreadableSavedDraft {
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
        case .review:
            if viewModel.isDrillingInFromBatch { return viewModel.draft.title }
            return presentation == .primaryTab ? "Review Workout" : "Paste or Type"
        case .imported: return presentation == .primaryTab ? "Workout Added" : "Imported"
        default: return presentation == .primaryTab ? "Add Workout" : "Paste or Type"
        }
    }

    /// Review Workout intents and `marble://import` route to the primary editor.
    /// The staged text never enters a URL and is consumed by exactly this root
    /// destination, then reviewed through the same parser as direct input.
    private func consumePendingTextImportIfNeeded() {
        guard presentation == .primaryTab,
              let seed = PendingTextImport.consume() else { return }
        let incoming = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        if !current.isEmpty, current != incoming {
            pendingIncomingText = incoming
            showingIncomingTextChoice = true
            return
        }
        viewModel.startNewWorkout(with: incoming)
        Task { await viewModel.preview(in: modelContext) }
    }

    private func applyIncomingText(replacing: Bool) {
        guard let incoming = pendingIncomingText else { return }
        pendingIncomingText = nil
        if replacing {
            viewModel.startNewWorkout(with: incoming)
        } else {
            viewModel.ingestPastedText(incoming)
        }
        Task { await viewModel.preview(in: modelContext) }
    }

    private func ingestFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            viewModel.errorMessage = "Couldn't open that file. Try a .txt or .csv export."
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

    private func refreshSavedSheetDraft() {
        guard presentation == .primaryTab else { return }
        let url = WorkoutEntryDraftStore.applicationStore(slot: "sheet").url
        hasSavedSheetDraft = FileManager.default.fileExists(atPath: url.path)
    }

    private func discardCurrentDraft() {
        // Capture and clear pending requests before reset changes recovery state.
        // Discarding an older draft should open the selected repeat/handoff.
        let incomingReview = pendingReviewDraft
        let incomingText = pendingIncomingText
        pendingReviewDraft = nil
        pendingIncomingText = nil
        if let incomingReview {
            viewModel.startReview(with: incomingReview)
        } else if let incomingText {
            viewModel.startNewWorkout(with: incomingText)
            Task { await viewModel.preview(in: modelContext) }
        } else {
            viewModel.reset()
            if presentation == .sheet { dismiss() }
        }
    }
}

/// Review headings stay legible at the scroll edges in both appearances.
private struct WorkoutReviewSectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(MarbleTypography.sectionTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.backgroundColor(for: colorScheme))
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
    var onKeepNote: (String) -> Void

    @State private var editedText: String
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, index: Int, onSubmit: @escaping (String) -> Void, onKeepNote: @escaping (String) -> Void) {
        self.text = text
        self.index = index
        self.onSubmit = onSubmit
        self.onKeepNote = onKeepNote
        _editedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            TextField("Workout detail", text: $editedText, axis: .vertical)
                .font(MarbleTypography.rowSubtitle)
                .onSubmit { onSubmit(editedText) }
                .submitLabel(.done)
                .accessibilityIdentifier("TextEntry.Unparsed.Line.\(index)")
            Button { onSubmit(editedText) } label: {
                Text("Try again")
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
                .accessibilityIdentifier("TextEntry.Unparsed.Retry.\(index)")
            Button { onKeepNote(editedText) } label: {
                Text("Keep in workout notes")
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
                .accessibilityIdentifier("TextEntry.Unparsed.KeepNote.\(index)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .onChange(of: text) { _, newValue in editedText = newValue }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            TextField("Exercise name", text: $exercise.name)
                .font(MarbleTypography.rowTitle)
                .onChange(of: exercise.name) { _, _ in onNameChanged() }
                .accessibilityIdentifier("TextEntry.Exercise.Name.\(exercise.id.uuidString)")

            ImportExerciseMatchRow(
                exerciseName: exercise.name,
                exerciseID: exercise.id,
                idPrefix: "TextEntry",
                resolution: resolution,
                onChoose: onChoose
            )

            if !exercise.sets.isEmpty && exercise.sets.allSatisfy({ !$0.hasAnyValue }) {
                Text("\(exercise.sets.count) sets recorded. Reps were not specified; you can leave them blank.")
                    .font(MarbleTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("TextEntry.Exercise.CountOnly.\(exercise.id.uuidString)")
            }

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
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: MarbleSpacing.s))
                : AnyLayout(HStackLayout(spacing: MarbleSpacing.s))
            layout {
                WorkoutReviewSectionHeader(title: "Exercise")
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                HStack(spacing: MarbleSpacing.s) {
                    Button { onMove(-1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
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
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
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
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("TextEntry.Exercise.Remove.\(exercise.id.uuidString)")
                }
            }
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

            ImportSetAnnotationFields(idPrefix: "TextEntry", set: $set)
        }
        .padding(.vertical, MarbleSpacing.xs)
    }
}
