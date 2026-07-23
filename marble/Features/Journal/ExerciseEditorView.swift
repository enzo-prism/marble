import SwiftData
import SwiftUI

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @Query(sort: \PlannedSet.createdAt)
    private var plannedSets: [PlannedSet]

    @Query(sort: \SprintPrescription.createdAt)
    private var sprintPrescriptions: [SprintPrescription]

    let exercise: Exercise?
    let initialName: String
    let onSave: ((Exercise) -> Void)?
    let onDelete: (() -> Void)?
    let dismissAfterSave: Bool

    @State private var draft = ExerciseEditorDraft.new()
    @State private var originalDraft = ExerciseEditorDraft.new()
    @State private var didInitialize = false
    @State private var didAttemptSave = false
    @State private var showAdvanced = false
    @State private var showSaveError = false
    @State private var showDeleteError = false
    @State private var showHistoryConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteBlocked = false
    @State private var showDiscardConfirmation = false
    @State private var validationScrollRequest = 0
    @FocusState private var focusedField: Field?

    init(
        exercise: Exercise?,
        initialName: String = "",
        dismissAfterSave: Bool = true,
        onSave: ((Exercise) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        self.initialName = initialName
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if didAttemptSave, !validationErrors.isEmpty {
                        validationSection
                            .id("ExerciseEditor.Validation")
                    }

                    basicsSection
                    typeSection

                    if existingHistoryCount > 0 || plannedSetCount > 0 {
                        historySection
                    }

                    typeSpecificSections
                    defaultsSection
                    advancedSection

                    if exercise != nil {
                        deleteSection
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundColor(for: colorScheme))
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("ExerciseEditor.List")
                .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarGlassBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: requestDismiss)
                            .accessibilityIdentifier("ExerciseEditor.Cancel")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: requestSave)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("ExerciseEditor.Save")
                    }
                }
                .onChange(of: validationScrollRequest) { _, _ in
                    withAnimation { proxy.scrollTo("ExerciseEditor.Validation", anchor: .top) }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: configureInitialState)
        .onChange(of: draft.customIconEmoji) { _, newValue in
            let sanitized = newValue.firstExerciseEmoji ?? ""
            if sanitized != newValue { draft.customIconEmoji = sanitized }
        }
        .confirmationDialog("Save changes that affect workouts?", isPresented: $showHistoryConfirmation) {
            Button("Save Changes") { save() }
                .accessibilityIdentifier("ExerciseEditor.HistoryConfirm")
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("ExerciseEditor.HistoryCancel")
        } message: {
            Text(impactConfirmationMessage)
        }
        .confirmationDialog("Delete \(exercise?.name ?? "this exercise")?", isPresented: $showDeleteConfirmation) {
            Button("Delete Exercise", role: .destructive, action: deleteExercise)
                .accessibilityIdentifier("ExerciseEditor.Delete.Confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("ExerciseEditor.Delete.Cancel")
        } message: {
            Text("This removes the exercise from Marble. This can't be undone.")
        }
        .confirmationDialog("Discard your changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard Changes", role: .destructive) { dismiss() }
                .accessibilityIdentifier("ExerciseEditor.Discard.Confirm")
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("ExerciseEditor.Discard.Cancel")
        }
        .alert("Exercise Is In Use", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteBlockedMessage)
        }
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Marble couldn't save this exercise. Please try again.")
        }
        .alert("Unable to Delete", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Marble couldn't delete this exercise. Please try again.")
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                TextField("Exercise name", text: $draft.name, prompt: Text("e.g. Bench Press"))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("ExerciseEditor.Name")

                if shouldShowNameError, let nameError {
                    Label(nameError, systemImage: "exclamationmark.circle")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("ExerciseEditor.NameError")
                }
            }

            HStack(spacing: MarbleSpacing.s) {
                ExerciseIconView(icon: draftDisplayIcon, fontSize: 22, frameSize: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(draft.category.displayName)
                    Text(draft.kind.subtitle)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ExerciseEditor.Summary")

            Picker("Category", selection: $draft.category) {
                ForEach(ExerciseCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .accessibilityIdentifier("ExerciseEditor.Category")
        }
    }

    private var typeSection: some View {
        Section {
            LazyVGrid(columns: typeColumns, spacing: MarbleSpacing.s) {
                ForEach(ExerciseKind.allCases) { kind in
                    Button {
                        select(kind)
                    } label: {
                        ExerciseKindCard(kind: kind, isSelected: draft.kind == kind)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExerciseEditor.Template.\(kind.id)")
                }
            }
            .padding(.vertical, MarbleSpacing.xs)
            .accessibilityIdentifier("ExerciseEditor.Templates")
        } header: {
            Text("How You Track It")
        } footer: {
            Text("Choose the closest match. Marble sets up the fields you need and hides the rest.")
        }
    }

    @ViewBuilder
    private var typeSpecificSections: some View {
        if draft.kind == .strength || draft.kind == .dualDumbbell || draft.kind == .weightedBodyweight {
            Section("Weight Entry") {
                Picker("Enter weight as", selection: $draft.resistanceTrackingStyle) {
                    ForEach(ResistanceTrackingStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .accessibilityIdentifier("ExerciseEditor.WeightTrackingStyle")

                Text(draft.resistanceTrackingStyle.editorDescription)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }

        if draft.kind == .run {
            Section("Distance") {
                Picker("Default unit", selection: $draft.preferredDistanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .accessibilityIdentifier("ExerciseEditor.DistanceUnit")
            }
        }

        if draft.kind == .sprint {
            Section("Sprint Goal") {
                SprintPrescriptionEditorView(
                    isEnabled: .constant(true),
                    distance: $draft.sprintDistance,
                    distanceUnit: $draft.preferredDistanceUnit,
                    repetitionCount: $draft.sprintRepetitionCount,
                    targetMode: $draft.sprintTargetMode,
                    targetSeconds: $draft.sprintTargetSeconds,
                    targetLowerSeconds: $draft.sprintTargetLowerSeconds,
                    targetUpperSeconds: $draft.sprintTargetUpperSeconds,
                    showsEnableToggle: false
                )

                if didAttemptSave, !draft.sprintErrors.isEmpty {
                    ForEach(draft.sprintErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
            }
        }

        if draft.kind == .custom {
            Section("Fields To Track") {
                ForEach(ExerciseMetricKind.allCases) { metric in
                    Picker(metricLabel(metric), selection: requirementBinding(for: metric)) {
                        Text("Off").tag(MetricRequirement.none)
                        Text("Optional").tag(MetricRequirement.optional)
                        Text("Every set").tag(MetricRequirement.required)
                    }
                    .accessibilityIdentifier("ExerciseEditor.Metric.\(metric.id)")
                }

                if didAttemptSave, let trackingError = draft.trackingError {
                    Label(trackingError, systemImage: "exclamationmark.circle")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                if draft.metrics.usesWeight {
                    Picker("Enter weight as", selection: $draft.resistanceTrackingStyle) {
                        ForEach(ResistanceTrackingStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .accessibilityIdentifier("ExerciseEditor.WeightTrackingStyle")
                }

                if draft.metrics.usesDistance {
                    Picker("Distance unit", selection: $draft.preferredDistanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .accessibilityIdentifier("ExerciseEditor.DistanceUnit")
                }
            }
        }
    }

    private var defaultsSection: some View {
        Section("Workout Default") {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack {
                    Text("Rest after each set")
                    Spacer()
                    Text(DateHelper.formattedDuration(seconds: draft.defaultRestSeconds))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .monospacedDigit()
                }

                RestPicker(
                    restSeconds: $draft.defaultRestSeconds,
                    presets: draft.kind == .sprint ? [0, 30, 60, 90, 120, 180, 300, 480, 600] : [30, 45, 60, 75, 90, 120, 180]
                )
                .accessibilityIdentifier(draft.kind == .sprint ? "ExerciseEditor.Sprint.Rest" : "ExerciseEditor.DefaultRest")
            }
        }
    }

    private var advancedSection: some View {
        Section {
            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Label("Appearance & Advanced", systemImage: "slider.horizontal.3")
                        .font(MarbleTypography.rowTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ExerciseEditor.Advanced")

            if showAdvanced {
                Toggle("Favorite", isOn: $draft.isFavorite)
                    .accessibilityIdentifier("ExerciseEditor.Favorite")

                Picker("Icon", selection: $draft.iconSource) {
                    Text("Category icon").tag(ExerciseIconSource.category)
                    Text("Emoji").tag(ExerciseIconSource.emoji)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ExerciseEditor.IconMode")

                if draft.iconSource == .emoji {
                    TextField("Emoji", text: $draft.customIconEmoji, prompt: Text("e.g. 💪"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ExerciseEditor.CustomEmoji")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MarbleSpacing.xs) {
                            ForEach(Array(draft.category.emojiSuggestions.enumerated()), id: \.offset) { index, emoji in
                                Button {
                                    draft.customIconEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                                .fill(Theme.chipFillColor(for: colorScheme))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Use \(emoji) icon")
                                .accessibilityIdentifier("ExerciseEditor.EmojiSuggestion.\(index)")
                            }
                        }
                    }

                    if didAttemptSave, let iconError = draft.iconError {
                        Label(iconError, systemImage: "exclamationmark.circle")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }

                if draft.kind != .custom && draft.kind != .sprint {
                    Button("Customize Tracked Fields") {
                        draft.apply(.custom)
                    }
                    .accessibilityIdentifier("ExerciseEditor.CustomizeTracking")
                }
            }
        }
    }

    private var historySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(usageSummary)
                        .font(MarbleTypography.rowTitle)
                    Text(historyImpactText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            } icon: {
                Image(systemName: changesUsedWorkouts ? "exclamationmark.triangle" : "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("ExerciseEditor.HistoryImpact")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive, action: requestDelete) {
                Label("Delete Exercise", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("ExerciseEditor.Delete")
        } footer: {
            if loggedSetCount > 0 || plannedSetCount > 0 {
                Text(deleteBlockedMessage)
            } else {
                Text("Only exercises with no logged sets or planned workouts can be deleted.")
            }
        }
    }

    private var validationSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text("Finish these details")
                        .font(MarbleTypography.rowTitle)
                    ForEach(validationErrors, id: \.self) { error in
                        Text(error)
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .accessibilityIdentifier("ExerciseEditor.Validation")
        }
    }

    private var typeColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: MarbleSpacing.s), GridItem(.flexible())]
    }

    private var currentPrescription: SprintPrescription? {
        guard let exercise else { return nil }
        return sprintPrescriptions.first { $0.exerciseID == exercise.id }
    }

    private var draftDisplayIcon: ExerciseDisplayIcon {
        if draft.iconSource == .emoji, let emoji = draft.resolvedCustomIconEmoji {
            return .emoji(emoji)
        }
        return .symbol(draft.category.symbolName)
    }

    private var nameError: String? {
        draft.nameError(existingExercises: exercises, excluding: exercise?.id)
    }

    private var shouldShowNameError: Bool {
        didAttemptSave || (!draft.trimmedName.isEmpty && nameError != nil)
    }

    private var validationErrors: [String] {
        draft.validationErrors(existingExercises: exercises, excluding: exercise?.id)
    }

    private var existingHistoryCount: Int { loggedSetCount }

    private var loggedSetCount: Int {
        guard let id = exercise?.id else { return 0 }
        return entries.lazy.filter { $0.exercise.id == id }.count
    }

    private var plannedSetCount: Int {
        guard let id = exercise?.id else { return 0 }
        return plannedSets.lazy.filter { $0.exercise.id == id }.count
    }

    private var draftChangesHistory: Bool {
        guard let exercise else { return false }
        return draft.changesHistoricalInterpretation(from: exercise)
    }

    private var draftChangesPlannedWorkouts: Bool {
        exercise != nil && draft.changesPlannedWorkoutBehavior(from: originalDraft)
    }

    private var changesUsedWorkouts: Bool {
        (loggedSetCount > 0 && draftChangesHistory) ||
        (plannedSetCount > 0 && draftChangesPlannedWorkouts)
    }

    private var usageSummary: String {
        var uses: [String] = []
        if loggedSetCount > 0 {
            uses.append("\(loggedSetCount) logged \(loggedSetCount == 1 ? "set" : "sets")")
        }
        if plannedSetCount > 0 {
            uses.append("\(plannedSetCount) planned workout \(plannedSetCount == 1 ? "slot" : "slots")")
        }
        return "Used by \(uses.joined(separator: " and "))"
    }

    private var impactConfirmationMessage: String {
        var impacts: [String] = []
        if loggedSetCount > 0, draftChangesHistory {
            impacts.append("how \(loggedSetCount) logged \(loggedSetCount == 1 ? "set is" : "sets are") interpreted")
        }
        if plannedSetCount > 0, draftChangesPlannedWorkouts {
            impacts.append("\(plannedSetCount) planned workout \(plannedSetCount == 1 ? "slot" : "slots")")
        }
        return "These changes affect \(impacts.joined(separator: " and "))."
    }

    private var historyImpactText: String {
        if changesUsedWorkouts {
            return "These changes affect saved workout data. Marble will ask before saving."
        }
        return "Name, category, icon, favorite, and rest changes are safe for existing history."
    }

    private var isDirty: Bool {
        didInitialize && draft != originalDraft
    }

    private var deleteBlockedMessage: String {
        var uses: [String] = []
        if loggedSetCount > 0 {
            uses.append("\(loggedSetCount) logged \(loggedSetCount == 1 ? "set" : "sets")")
        }
        if plannedSetCount > 0 {
            uses.append("\(plannedSetCount) planned workout \(plannedSetCount == 1 ? "slot" : "slots")")
        }
        guard !uses.isEmpty else { return "This exercise isn't used by any saved sets or plans." }
        return "Remove it from \(uses.joined(separator: " and ")) before deleting it."
    }

    private func metricLabel(_ metric: ExerciseMetricKind) -> String {
        switch metric {
        case .weight: "Weight"
        case .reps: "Repetitions"
        case .distance: "Distance"
        case .duration: "Time"
        }
    }

    private func requirementBinding(for metric: ExerciseMetricKind) -> Binding<MetricRequirement> {
        Binding(
            get: { draft.metrics.requirement(for: metric) },
            set: { draft.metrics.setRequirement($0, for: metric) }
        )
    }

    private func configureInitialState() {
        guard !didInitialize else { return }
        let configuredDraft: ExerciseEditorDraft
        if let exercise {
            configuredDraft = ExerciseEditorDraft(exercise: exercise, prescription: currentPrescription)
        } else {
            configuredDraft = .new(initialName: initialName)
        }
        draft = configuredDraft
        originalDraft = configuredDraft
        didInitialize = true
        if exercise == nil, configuredDraft.trimmedName.isEmpty {
            DispatchQueue.main.async { focusedField = .name }
        }
    }

    private func select(_ kind: ExerciseKind) {
        focusedField = nil
        draft.apply(kind)
        MarbleHaptics.selection()
    }

    private func requestDismiss() {
        focusedField = nil
        if isDirty {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func requestSave() {
        focusedField = nil
        didAttemptSave = true
        guard validationErrors.isEmpty else {
            if nameError != nil { focusedField = .name }
            validationScrollRequest += 1
            MarbleHaptics.warning()
            return
        }
        if changesUsedWorkouts {
            showHistoryConfirmation = true
            return
        }
        save()
    }

    private func save() {
        let savedExercise: Exercise
        if let exercise {
            applyDraft(to: exercise)
            savedExercise = exercise
        } else {
            let newExercise = Exercise(
                name: draft.trimmedName,
                category: draft.category,
                customIconEmoji: draft.iconSource == .emoji ? draft.resolvedCustomIconEmoji : nil,
                resistanceTrackingStyle: draft.resistanceTrackingStyle,
                preferredDistanceUnit: draft.preferredDistanceUnit,
                metrics: draft.metrics,
                defaultRestSeconds: draft.defaultRestSeconds,
                isFavorite: draft.isFavorite
            )
            modelContext.insert(newExercise)
            savedExercise = newExercise
        }

        persistSprintPrescription(for: savedExercise)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            showSaveError = true
            return
        }

        originalDraft = draft
        MarbleHaptics.success()
        // A created or renamed exercise must reach Siri and Spotlight now, not
        // at the next cold launch (`reindexAll()` otherwise only runs from
        // ContentView's launch task): the reindex refreshes the Spotlight row,
        // and the shortcut re-registration keeps the parameterised "Log a set
        // of <exercise>" phrase resolving against the current names — an Apple
        // requirement whenever the entities behind such a phrase change.
        Task { await ExerciseSpotlightIndex.reindexAll() }
        MarbleShortcuts.updateAppShortcutParameters()
        onSave?(savedExercise)
        if dismissAfterSave { dismiss() }
    }

    private func applyDraft(to exercise: Exercise) {
        exercise.name = draft.trimmedName
        exercise.category = draft.category
        exercise.setCustomIconEmoji(draft.iconSource == .emoji ? draft.resolvedCustomIconEmoji : nil)
        exercise.setResistanceTrackingStyle(draft.resistanceTrackingStyle)
        exercise.setPreferredDistanceUnit(draft.preferredDistanceUnit)
        exercise.metrics = draft.metrics
        exercise.defaultRestSeconds = draft.defaultRestSeconds
        exercise.isFavorite = draft.isFavorite
    }

    private func persistSprintPrescription(for exercise: Exercise) {
        let existing = sprintPrescriptions.first { $0.exerciseID == exercise.id }
        guard draft.usesSprintPrescription else {
            if let existing { modelContext.delete(existing) }
            return
        }

        guard let distance = draft.sprintDistance else { return }
        let lower: Int
        let upper: Int
        switch draft.sprintTargetMode {
        case .time:
            guard let target = draft.sprintTargetSeconds else { return }
            lower = target
            upper = target
        case .range:
            guard let fast = draft.sprintTargetLowerSeconds,
                  let slow = draft.sprintTargetUpperSeconds else { return }
            lower = fast
            upper = slow
        }

        let now = AppEnvironment.now
        if let existing {
            existing.distance = distance
            existing.repetitionCount = draft.sprintRepetitionCount
            existing.targetLowerSeconds = lower
            existing.targetUpperSeconds = upper
            existing.updatedAt = now
        } else {
            modelContext.insert(SprintPrescription(
                exerciseID: exercise.id,
                distance: distance,
                repetitionCount: draft.sprintRepetitionCount,
                targetLowerSeconds: lower,
                targetUpperSeconds: upper,
                createdAt: now,
                updatedAt: now
            ))
        }
    }

    private func requestDelete() {
        if loggedSetCount > 0 || plannedSetCount > 0 {
            showDeleteBlocked = true
        } else {
            showDeleteConfirmation = true
        }
    }

    private func deleteExercise() {
        guard let exercise else { return }
        guard loggedSetCount == 0, plannedSetCount == 0 else {
            showDeleteBlocked = true
            return
        }
        // Captured before the delete: the model is not safe to read once it
        // has been removed from the context, and the Spotlight task below
        // outlives this view.
        let deletedID = exercise.id
        sprintPrescriptions
            .filter { $0.exerciseID == exercise.id }
            .forEach(modelContext.delete)
        modelContext.delete(exercise)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            showDeleteError = true
            return
        }
        MarbleHaptics.warning()
        // Per-item Spotlight removal — a reindex alone refreshes surviving
        // rows but never drops the deleted one, which is how deleted exercises
        // stayed searchable until the next cold launch. The shortcut phrase
        // update stops Siri offering the dead name in "Log a set of …".
        Task { await ExerciseSpotlightIndex.remove(exerciseID: deletedID) }
        MarbleShortcuts.updateAppShortcutParameters()
        onDelete?()
        dismiss()
    }
}

private extension ExerciseEditorView {
    enum Field: Hashable { case name }
}

private struct ExerciseKindCard: View {
    let kind: ExerciseKind
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: MarbleSpacing.xs) {
            Image(systemName: kind.symbolName)
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(kind.title)
                    .font(MarbleTypography.rowTitle)
                Text(kind.subtitle)
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .fill(isSelected ? Theme.chipFillColor(for: colorScheme) : Theme.backgroundColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(
                    isSelected ? Theme.primaryTextColor(for: colorScheme) : Theme.dividerColor(for: colorScheme),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title), \(kind.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
