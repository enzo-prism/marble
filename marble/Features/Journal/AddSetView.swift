import SwiftUI
import SwiftData
import UIKit

struct AddSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Binding private var isPresented: Bool
    @State private var selectedExerciseID: UUID?
    @State private var selectedExerciseSnapshot: ExerciseSnapshot?
    @State private var performedAt: Date
    @State private var weight: Double?
    @State private var weightUnit: WeightUnit = .lb
    @State private var reps: Int?
    @State private var durationSeconds: Int?
    @State private var difficulty: Int = 8
    @State private var restAfterSeconds: Int = 60
    @State private var notes: String = ""
    @State private var showNotes = false
    @State private var addedLoad = false
    @State private var showRestTimer = false
    @State private var didInitialize = false
    @State private var showSaveError = false
    @State private var showMissingExercise = false
    @State private var lastEntry: SetEntry?
    @State private var showingProgress = false
    private let repsRange: ClosedRange<Int> = 1...20
    private let defaultRepsValue: Int = 10

    init(initialPerformedAt: Date = AppEnvironment.now, initialExercise: Exercise? = nil, isPresented: Binding<Bool> = .constant(true)) {
        _performedAt = State(initialValue: initialPerformedAt)
        _selectedExerciseID = State(initialValue: initialExercise?.id)
        _isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        NavigationLink {
                            ExercisePickerView(selectedExercise: exerciseSelection)
                    } label: {
                        HStack {
                            Text("Exercise")
                                .font(MarbleTypography.rowTitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Spacer()
                            Text(selectedExerciseSnapshot?.name ?? "Select")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                        .padding(.vertical, MarbleSpacing.s)
                    }
                    .accessibilityIdentifier("AddSet.ExercisePicker")
                    .accessibilityValue(selectedExerciseSnapshot?.name ?? "Select")
                }

                if let exercise = selectedExerciseSnapshot {
                    Section {
                        LastTimeCardView(
                            content: lastTimeContent,
                            onViewProgress: {
                                showingProgress = true
                            }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier("AddSet.LastTime")
                    } header: {
                        SectionHeaderView(title: "Last time")
                    }

                    Section {
                        if exercise.metrics.usesWeight {
                            if exercise.metrics.weight == .optional {
                                Toggle("Added load", isOn: $addedLoad)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .padding(.vertical, MarbleSpacing.s)
                                    .accessibilityIdentifier("AddSet.AddedLoad")
                            }

                            if exercise.metrics.weightIsRequired || addedLoad {
                                HStack {
                                    OptionalNumberField(title: "Weight", formatter: Formatters.weight, value: $weight, accessibilityIdentifier: "AddSet.Weight")
                                    Picker("Unit", selection: $weightUnit) {
                                        ForEach(WeightUnit.allCases) { unit in
                                            Text(unit.symbol).tag(unit)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .accessibilityIdentifier("AddSet.WeightUnit")
                                }
                                .padding(.vertical, MarbleSpacing.s)
                            }
                        }

                        if exercise.metrics.usesReps {
                            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                HStack {
                                    Text("Reps")
                                        .font(MarbleTypography.rowTitle)
                                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                    Spacer()
                                    Text("\(repsDisplayValue)")
                                        .font(MarbleTypography.rowSubtitle)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .monospacedDigit()
                                }

                                Slider(value: repsSliderValue, in: Double(repsRange.lowerBound)...Double(repsRange.upperBound), step: 1)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .accessibilityIdentifier("AddSet.Reps")
                                    .accessibilityLabel("Reps")
                                    .accessibilityValue("\(repsDisplayValue) reps")
                            }
                            .padding(.vertical, MarbleSpacing.s)
                        }

                        if exercise.metrics.usesDuration {
                            HStack {
                                Text("Duration")
                                    .font(MarbleTypography.rowTitle)
                                Spacer()
                                DurationPicker(durationSeconds: $durationSeconds)
                                    .accessibilityIdentifier("AddSet.Duration")
                            }
                            .padding(.vertical, MarbleSpacing.s)
                        }
                    } header: {
                        SectionHeaderView(title: "Metrics")
                    }

                    Section {
                        RPEPicker(value: $difficulty)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.RPE")
                            .padding(.vertical, MarbleSpacing.s)
                    }

                    Section {
                        RestPicker(restSeconds: $restAfterSeconds)
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.RestPicker")
                            .padding(.vertical, MarbleSpacing.s)
                    }

                    Section {
                        DatePicker("Performed", selection: $performedAt)
                            .tint(Theme.dividerColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.PerformedAt")
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .padding(.vertical, MarbleSpacing.s)
                        HStack {
                            Text("Now")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            performedAt = AppEnvironment.now
                        }
                        .accessibilityIdentifier("AddSet.Now")
                        .accessibilityLabel("Now")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            performedAt = AppEnvironment.now
                        }
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .padding(.vertical, MarbleSpacing.s)
                    }

                    Section {
                        if showNotes || !notes.isEmpty {
                            TextField("Notes", text: $notes, axis: .vertical)
                                .marbleFieldStyle()
                                .accessibilityIdentifier("AddSet.Notes")
                                .padding(.vertical, MarbleSpacing.s)
                        } else {
                            Button("Add note") {
                                showNotes = true
                            }
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("AddSet.AddNote")
                            .padding(.vertical, MarbleSpacing.s)
                        }
                    }
                }

                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("AddSet.List")
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .safeAreaInset(edge: .bottom) {
                saveButtons
            }
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .onChange(of: selectedExerciseID) { _, newValue in
                guard let newValue else {
                    selectedExerciseSnapshot = nil
                    lastEntry = nil
                    return
                }
                hydrateSelection(id: newValue, shouldApplyDefaults: true)
            }
            .onAppear {
                validateSelection()
                guard !didInitialize else { return }
                if let selectedExerciseID {
                    hydrateSelection(id: selectedExerciseID, shouldApplyDefaults: true)
                } else {
                    loadInitialExercise()
                }
                didInitialize = true
            }
            .sheet(isPresented: $showRestTimer) {
                RestTimerView(totalSeconds: restAfterSeconds)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .sheetGlassBackground()
            }
            .sheet(isPresented: $showingProgress) {
                if let selectedExerciseID, let exercise = fetchExercise(id: selectedExerciseID) {
                    ExerciseProgressView(exercise: exercise)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .sheetGlassBackground()
                } else {
                    Text("Exercise not found")
                        .font(MarbleTypography.body)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                        .sheetGlassBackground()
                }
            }
            .alert("Unable to Save", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't save this set. Please try again.")
            }
            .alert("Exercise Removed", isPresented: $showMissingExercise) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That exercise was removed. Choose another one before saving.")
            }
        }
    }

    private var exerciseSelection: Binding<Exercise?> {
        Binding(
            get: { nil },
            set: { newValue in
                guard let newValue else {
                    selectedExerciseID = nil
                    selectedExerciseSnapshot = nil
                    return
                }
                selectExercise(newValue, lastEntry: fetchLastEntry(for: newValue.id))
            }
        )
    }

    private var canSave: Bool {
        guard let exercise = selectedExerciseSnapshot else { return false }
        if exercise.metrics.weightIsRequired, weight == nil {
            return false
        }
        if exercise.metrics.repsIsRequired, reps == nil {
            return false
        }
        if exercise.metrics.durationIsRequired, (durationSeconds ?? 0) == 0 {
            return false
        }
        return true
    }

    private var effectiveCanSave: Bool {
        guard selectedExerciseSnapshot != nil else { return false }
        return canSave || TestHooks.isUITesting
    }

    private var repsDisplayValue: Int {
        clampReps(reps ?? defaultRepsValue)
    }

    private var repsSliderValue: Binding<Double> {
        Binding(
            get: { Double(repsDisplayValue) },
            set: { newValue in
                reps = clampReps(Int(newValue.rounded()))
            }
        )
    }

    private var lastTimeContent: LastTimeContent {
        guard let exercise = selectedExerciseSnapshot, let lastEntry else {
            return LastTimeContent(
                summaryText: "No previous sets yet",
                relativeTimeText: nil,
                preciseDateText: nil,
                metaText: nil,
                notesText: nil,
                deltaText: nil,
                accessibilityLabel: "No previous sets yet"
            )
        }

        let summary = lastTimeSummary(for: lastEntry, metrics: exercise.metrics)
        let relativeTime = DateHelper.relativeTime(from: lastEntry.performedAt)
        let preciseTime = Formatters.fullDateTime.string(from: lastEntry.performedAt)
        let metaText = lastTimeMeta(for: lastEntry)
        let notesText = lastTimeNotes(for: lastEntry)
        let deltaText = deltaSummaryText(for: lastEntry, metrics: exercise.metrics)
        let accessibilityLabel = [summary, relativeTime, preciseTime, metaText, notesText, deltaText]
            .compactMap { $0 }
            .joined(separator: ", ")

        return LastTimeContent(
            summaryText: summary,
            relativeTimeText: relativeTime,
            preciseDateText: preciseTime,
            metaText: metaText,
            notesText: notesText,
            deltaText: deltaText,
            accessibilityLabel: accessibilityLabel
        )
    }

    private var saveButtons: some View {
        VStack(spacing: MarbleSpacing.s) {
            Button("Save") {
                save(startRest: false)
            }
            .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
            .allowsHitTesting(effectiveCanSave)
            .accessibilityIdentifier("AddSet.Save")

            if restAfterSeconds > 0, canSave {
                Button("Save & Start Rest") {
                    save(startRest: true)
                }
                .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
                .allowsHitTesting(effectiveCanSave)
                .accessibilityIdentifier("AddSet.SaveStartRest")
            }
        }
        .padding(.horizontal, MarbleLayout.pagePadding)
        .padding(.top, MarbleSpacing.s)
        .padding(.bottom, MarbleSpacing.m)
        .background(Theme.backgroundColor(for: colorScheme))
        .overlay(alignment: .top) {
            Divider()
                .background(Theme.dividerColor(for: colorScheme))
        }
    }

    private func loadInitialExercise() {
        if let recent = fetchMostRecentEntry() {
            selectExercise(recent.exercise, lastEntry: recent)
            performedAt = DateHelper.merge(day: performedAt, time: AppEnvironment.now)
            return
        }

        if let favorite = fetchFavoriteExercise() {
            selectExercise(favorite, lastEntry: fetchLastEntry(for: favorite.id))
            return
        }

        if let first = fetchFirstExercise() {
            selectExercise(first, lastEntry: fetchLastEntry(for: first.id))
        }
    }

    private func applyDefaults(for exercise: ExerciseSnapshot, lastEntry: SetEntry?) {
        if let lastEntry {
            weight = lastEntry.weight
            weightUnit = lastEntry.weightUnit
            if exercise.metrics.usesReps {
                reps = lastEntry.reps.map { clampReps($0) } ?? defaultRepsValue
            } else {
                reps = nil
            }
            durationSeconds = lastEntry.durationSeconds
            difficulty = lastEntry.difficulty
            restAfterSeconds = lastEntry.restAfterSeconds
            addedLoad = lastEntry.weight != nil
            return
        }
        weight = nil
        reps = exercise.metrics.usesReps ? defaultRepsValue : nil
        durationSeconds = exercise.metrics.usesDuration ? 60 : nil
        difficulty = 8
        restAfterSeconds = exercise.defaultRestSeconds
        addedLoad = false
    }

    private func save(startRest: Bool) {
        dismissKeyboard()
        guard let selectedExerciseID else {
            showMissingExercise = selectedExerciseSnapshot != nil
            return
        }
        guard let exercise = fetchExercise(id: selectedExerciseID) else {
            selectedExerciseSnapshot = nil
            showMissingExercise = true
            return
        }
        guard canSave || TestHooks.isUITesting else { return }

        let metrics = exercise.metrics
        let resolvedWeight: Double? = {
            if metrics.weight == .optional, !addedLoad {
                return nil
            }
            return weight
        }()

        let now = AppEnvironment.now
        let entry = SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: resolvedWeight,
            weightUnit: weightUnit,
            reps: metrics.usesReps ? reps : nil,
            durationSeconds: metrics.usesDuration ? durationSeconds : nil,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: notes.isEmpty ? nil : notes,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(entry)
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Save set failed: \(error)")
            #endif
            modelContext.rollback()
            showSaveError = true
            return
        }

        let snapshot = ExerciseSnapshot(exercise)
        if startRest {
            resetForm(for: snapshot, lastEntry: entry)
            showRestTimer = true
            return
        }

        closeSheet()
    }

    private func resetForm(for exercise: ExerciseSnapshot, lastEntry: SetEntry?) {
        selectedExerciseID = exercise.id
        selectedExerciseSnapshot = exercise
        self.lastEntry = lastEntry
        performedAt = AppEnvironment.now
        applyDefaults(for: exercise, lastEntry: lastEntry)
        notes = ""
        showNotes = false
    }

    private func closeSheet() {
        quickLog.isPresentingAddSet = false
        isPresented = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func clampReps(_ value: Int) -> Int {
        min(max(value, repsRange.lowerBound), repsRange.upperBound)
    }

    private func lastTimeSummary(for entry: SetEntry, metrics: ExerciseMetricsProfile) -> String {
        if metrics.usesDuration, let duration = entry.durationSeconds {
            return DateHelper.formattedClockDuration(seconds: duration)
        }

        if metrics.usesWeight, let weight = entry.weight {
            let weightText = formattedWeight(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                return "\(weightText) \(timesSymbol) \(reps)"
            }
            return weightText
        }

        if metrics.usesReps, let reps = entry.reps {
            return "\(reps) reps"
        }

        if let duration = entry.durationSeconds {
            return DateHelper.formattedClockDuration(seconds: duration)
        }

        return "No metrics"
    }

    private func lastTimeMeta(for entry: SetEntry) -> String? {
        var parts: [String] = []
        parts.append("RPE \(entry.difficulty)")
        if entry.restAfterSeconds > 0 {
            parts.append("Rest \(DateHelper.formattedDuration(seconds: entry.restAfterSeconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func lastTimeNotes(for entry: SetEntry) -> String? {
        let trimmed = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return "Notes: \(trimmed)"
    }

    private func deltaSummaryText(for entry: SetEntry, metrics: ExerciseMetricsProfile) -> String? {
        var deltas: [String] = []

        if metrics.usesWeight, (metrics.weightIsRequired || addedLoad),
           let currentWeight = weight,
           let lastWeight = entry.weight,
           entry.weightUnit == weightUnit {
            let diff = currentWeight - lastWeight
            let formatted = Formatters.weight.string(from: NSNumber(value: abs(diff))) ?? "\(abs(diff))"
            let sign = diff >= 0 ? "+" : "-"
            deltas.append("\(sign)\(formatted) \(weightUnit.symbol)")
        }

        if metrics.usesReps,
           let currentReps = reps,
           let lastReps = entry.reps {
            let diff = currentReps - lastReps
            let sign = diff >= 0 ? "+" : "-"
            let label = abs(diff) == 1 ? "rep" : "reps"
            deltas.append("\(sign)\(abs(diff)) \(label)")
        }

        if metrics.usesDuration,
           let currentDuration = durationSeconds,
           let lastDuration = entry.durationSeconds,
           currentDuration > 0,
           lastDuration > 0 {
            let diff = currentDuration - lastDuration
            let sign = diff >= 0 ? "+" : "-"
            let formatted = DateHelper.formattedClockDuration(seconds: abs(diff))
            deltas.append("\(sign)\(formatted)")
        }

        guard !deltas.isEmpty else { return nil }
        return "Delta vs last: " + deltas.joined(separator: " · ")
    }

    private func formattedWeight(_ weight: Double, unit: WeightUnit) -> String {
        let formatted = Formatters.weight.string(from: NSNumber(value: weight)) ?? "\(weight)"
        return "\(formatted) \(unit.symbol)"
    }

    private let timesSymbol = "\u{00D7}"
}

private extension AddSetView {
    struct ExerciseSnapshot: Equatable {
        let id: UUID
        let name: String
        let category: ExerciseCategory
        let metrics: ExerciseMetricsProfile
        let defaultRestSeconds: Int

        init(_ exercise: Exercise) {
            id = exercise.id
            name = exercise.name
            category = exercise.category
            metrics = exercise.metrics
            defaultRestSeconds = exercise.defaultRestSeconds
        }
    }

    func selectExercise(_ exercise: Exercise, lastEntry: SetEntry?) {
        let snapshot = ExerciseSnapshot(exercise)
        selectedExerciseID = snapshot.id
        selectedExerciseSnapshot = snapshot
        self.lastEntry = lastEntry
        applyDefaults(for: snapshot, lastEntry: lastEntry)
    }

    func hydrateSelection(id: UUID, shouldApplyDefaults: Bool) {
        guard let exercise = fetchExercise(id: id) else {
            selectedExerciseID = nil
            selectedExerciseSnapshot = nil
            lastEntry = nil
            showMissingExercise = true
            return
        }
        let snapshot = ExerciseSnapshot(exercise)
        selectedExerciseSnapshot = snapshot
        let recent = fetchLastEntry(for: id)
        lastEntry = recent
        if shouldApplyDefaults {
            applyDefaults(for: snapshot, lastEntry: recent)
        }
    }

    func validateSelection() {
        guard let id = selectedExerciseID else { return }
        guard let exercise = fetchExercise(id: id) else {
            selectedExerciseID = nil
            selectedExerciseSnapshot = nil
            lastEntry = nil
            showMissingExercise = true
            return
        }
        selectedExerciseSnapshot = ExerciseSnapshot(exercise)
        lastEntry = fetchLastEntry(for: id)
    }

    func fetchExercise(id: UUID) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchMostRecentEntry() -> SetEntry? {
        var descriptor = FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchLastEntry(for exerciseID: UUID) -> SetEntry? {
        SetEntryQueries.mostRecentEntry(for: exerciseID, in: modelContext)
    }

    func fetchFavoriteExercise() -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchFirstExercise() -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}

private struct LastTimeContent {
    let summaryText: String
    let relativeTimeText: String?
    let preciseDateText: String?
    let metaText: String?
    let notesText: String?
    let deltaText: String?
    let accessibilityLabel: String
}

private struct LastTimeCardView: View {
    let content: LastTimeContent
    let onViewProgress: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.marbleReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        let card = VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(content.summaryText)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Spacer()

                if let relativeTimeText = content.relativeTimeText {
                    Text(relativeTimeText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }

            if let deltaText = content.deltaText {
                Text(deltaText)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            if let metaText = content.metaText {
                Text(metaText)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            if let notesText = content.notesText {
                Text(notesText)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(2)
            }

            Button("View progress") {
                onViewProgress()
            }
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .tint(Theme.dividerColor(for: colorScheme))
            .accessibilityIdentifier("AddSet.LastTime.ViewProgress")
            .accessibilityLabel("View progress")
            .applyGlassButtonStyle()
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassTileBackground())
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibilityLabel)

        if reduceTransparency {
            card
        } else if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: MarbleSpacing.s) {
                card
            }
        } else {
            card
        }
    }
}
