import SwiftUI
import SwiftData
import UIKit
import Combine

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
    @State private var distance: Double?
    @State private var distanceUnit: DistanceUnit = .meters
    @State private var durationSeconds: Int?
    @State private var difficulty: Int = 8
    @State private var restAfterSeconds: Int = 60
    @State private var notes: String = ""
    @State private var showDetails = false
    @State private var addedLoad = false
    @State private var logReps = false
    @State private var logDistance = false
    @State private var logDuration = false
    @State private var isKeyboardVisible = false
    @State private var didInitialize = false
    @State private var showSaveError = false
    @State private var showMissingExercise = false
    @State private var lastEntry: SetEntry?
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
                            exercisePickerRow
                        }
                        .accessibilityIdentifier("AddSet.ExercisePicker")
                        .accessibilityValue(selectedExerciseSnapshot?.name ?? "Select")
                    }

                if let exercise = selectedExerciseSnapshot {
                    Section {
                        LastTimeCardView(content: lastTimeContent)
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
                                Toggle(ExerciseMetricKind.weight.optionalToggleTitle, isOn: $addedLoad)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .padding(.vertical, MarbleSpacing.s)
                                    .accessibilityIdentifier("AddSet.AddedLoad")
                            }

                            if shouldCaptureWeight(for: exercise.metrics) {
                                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                    HStack {
                                        OptionalNumberField(
                                            title: exercise.weightInputTitle,
                                            formatter: Formatters.weight,
                                            value: $weight,
                                            accessibilityIdentifier: "AddSet.Weight"
                                        )
                                        Picker("Unit", selection: $weightUnit) {
                                            ForEach(WeightUnit.allCases) { unit in
                                                Text(unit.symbol).tag(unit)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .tint(Theme.dividerColor(for: colorScheme))
                                        .accessibilityIdentifier("AddSet.WeightUnit")
                                    }

                                    Text(exercise.weightInputHelperText)
                                        .font(MarbleTypography.caption)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, MarbleSpacing.s)
                            }
                        }

                        if exercise.metrics.usesReps {
                            if exercise.metrics.reps == .optional {
                                Toggle(ExerciseMetricKind.reps.optionalToggleTitle, isOn: $logReps)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .padding(.vertical, MarbleSpacing.s)
                                    .accessibilityIdentifier("AddSet.LogReps")
                            }

                            if shouldCaptureReps(for: exercise.metrics) {
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
                        }

                        if exercise.metrics.usesDistance {
                            if exercise.metrics.distance == .optional {
                                Toggle(ExerciseMetricKind.distance.optionalToggleTitle, isOn: $logDistance)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .padding(.vertical, MarbleSpacing.s)
                                    .accessibilityIdentifier("AddSet.LogDistance")
                            }

                            if shouldCaptureDistance(for: exercise.metrics) {
                                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                    HStack {
                                        OptionalNumberField(
                                            title: "Distance",
                                            formatter: Formatters.distance,
                                            value: $distance,
                                            accessibilityIdentifier: "AddSet.Distance"
                                        )
                                        Picker("Unit", selection: $distanceUnit) {
                                            ForEach(DistanceUnit.allCases) { unit in
                                                Text(unit.symbol.uppercased()).tag(unit)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(Theme.dividerColor(for: colorScheme))
                                        .accessibilityIdentifier("AddSet.DistanceUnit")
                                    }

                                    Text("Track each effort in \(distanceUnit.title.lowercased()).")
                                        .font(MarbleTypography.caption)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, MarbleSpacing.s)
                            }
                        }

                        if exercise.metrics.usesDuration {
                            if exercise.metrics.durationSeconds == .optional {
                                Toggle(ExerciseMetricKind.duration.optionalToggleTitle, isOn: $logDuration)
                                    .tint(Theme.dividerColor(for: colorScheme))
                                    .padding(.vertical, MarbleSpacing.s)
                                    .accessibilityIdentifier("AddSet.LogDuration")
                            }

                            if shouldCaptureDuration(for: exercise.metrics) {
                                HStack {
                                    Text("Duration")
                                        .font(MarbleTypography.rowTitle)
                                    Spacer()
                                    DurationPicker(durationSeconds: $durationSeconds)
                                }
                                .padding(.vertical, MarbleSpacing.s)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("AddSet.Duration")
                            }
                        }
                    } header: {
                        SectionHeaderView(title: "Metrics")
                    }

                    Section {
                        TextField("Optional note", text: $notes, axis: .vertical)
                            .marbleFieldStyle()
                            .accessibilityIdentifier("AddSet.Notes")
                            .padding(.vertical, MarbleSpacing.s)
                    } header: {
                        SectionHeaderView(title: "Notes (optional)")
                    }

                    Section {
                        DisclosureGroup(isExpanded: $showDetails) {
                            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                                RPEPicker(value: $difficulty)

                                RestPicker(restSeconds: $restAfterSeconds)
                                    .accessibilityIdentifier("AddSet.RestPicker")

                                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                                    DatePicker("Performed", selection: $performedAt)
                                        .tint(Theme.dividerColor(for: colorScheme))
                                        .accessibilityIdentifier("AddSet.PerformedAt")
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
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, MarbleSpacing.s)
                        } label: {
                            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                                Text("Details (optional)")
                                    .font(MarbleTypography.sectionTitle)
                                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                                Text("Set your effort, rest time, and adjust when you performed the set.")
                                    .font(MarbleTypography.rowSubtitle)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("AddSet.DetailsDisclosure")
                        .accessibilityHint("Opens extra logging fields like difficulty, rest time, and performed time.")
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                    }

                    if showsInlineSave {
                        Section {
                            saveButtonRow
                                .listRowSeparator(.hidden)
                        }
                    }
                }

                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundColor(for: colorScheme))
                .accessibilityIdentifier("AddSet.List")
                .safeAreaInset(edge: .bottom) {
                    if !showsInlineSave && !isKeyboardVisible {
                        saveButtons
                    }
                }
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!effectiveCanSave)
                    .accessibilityIdentifier("AddSet.Save")
                }
            }
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
            .onChange(of: addedLoad) { _, newValue in
                if !newValue {
                    weight = nil
                }
            }
            .onChange(of: logReps) { _, newValue in
                if newValue, reps == nil {
                    reps = defaultRepsValue
                }
                if !newValue {
                    reps = nil
                }
            }
            .onChange(of: logDistance) { _, newValue in
                if newValue, distance == nil {
                    distance = 100
                }
                if !newValue {
                    distance = nil
                }
            }
            .onChange(of: logDuration) { _, newValue in
                if newValue, (durationSeconds ?? 0) == 0 {
                    durationSeconds = 60
                }
                if !newValue {
                    durationSeconds = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
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
        .marbleKeyboardToolbar(
            primaryAction: KeyboardToolbarAction(
                title: "Save",
                accessibilityIdentifier: "Keyboard.Save",
                isEnabled: effectiveCanSave,
                handler: save
            )
        )
    }

    private var exerciseSelection: Binding<Exercise?> {
        Binding(
            get: {
                guard let selectedExerciseID else { return nil }
                return fetchExercise(id: selectedExerciseID)
            },
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
        if shouldCaptureWeight(for: exercise.metrics), weight == nil {
            return false
        }
        if shouldCaptureReps(for: exercise.metrics), reps == nil {
            return false
        }
        if shouldCaptureDistance(for: exercise.metrics), distance == nil {
            return false
        }
        if shouldCaptureDuration(for: exercise.metrics), (durationSeconds ?? 0) == 0 {
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

    private var showsInlineSave: Bool {
        false
    }

    private var lastTimeContent: LastTimeContent {
        guard let exercise = selectedExerciseSnapshot, let lastEntry else {
            return LastTimeContent(
                metrics: [],
                loggedAtText: nil,
                emptyText: "No history for this exercise",
                accessibilityLabel: "No history for this exercise",
                hasHistory: false
            )
        }

        let metrics = lastTimeMetrics(for: lastEntry, metrics: exercise.metrics)
        let loggedAtText = "Logged \(Formatters.fullDateTime.string(from: lastEntry.performedAt))"
        let metricLabel = metrics.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        let accessibilityLabel = metricLabel.isEmpty ? loggedAtText : "\(metricLabel), \(loggedAtText)"

        return LastTimeContent(
            metrics: metrics,
            loggedAtText: loggedAtText,
            emptyText: nil,
            accessibilityLabel: accessibilityLabel,
            hasHistory: true
        )
    }

    private func lastTimeMetrics(for entry: SetEntry, metrics: ExerciseMetricsProfile) -> [LastTimeMetric] {
        var items: [LastTimeMetric] = []

        if metrics.usesWeight {
            if let weight = entry.weight {
                items.append(LastTimeMetric(label: "Weight", value: entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)))
            } else if metrics.weight == .optional {
                items.append(LastTimeMetric(label: "Weight", value: "Bodyweight"))
            }
        }

        if metrics.usesReps, let reps = entry.reps {
            items.append(LastTimeMetric(label: "Reps", value: "\(reps)"))
        }

        if metrics.usesDistance, let distance = entry.distance {
            items.append(LastTimeMetric(label: "Distance", value: entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit)))
        }

        if metrics.usesDuration, let duration = entry.durationSeconds {
            items.append(LastTimeMetric(label: "Duration", value: DateHelper.formattedClockDuration(seconds: duration)))
        }

        items.append(LastTimeMetric(label: "Rest", value: DateHelper.formattedDuration(seconds: entry.restAfterSeconds)))
        return items
    }

    private var saveButtons: some View {
        VStack(spacing: MarbleSpacing.s) {
            saveButtonContent
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

    private var saveButtonRow: some View {
        saveButtonContent
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .padding(.vertical, MarbleSpacing.s)
            .marbleRowInsets()
    }

    private var saveButtonContent: some View {
        Button("Save Set") {
            save()
        }
        .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: effectiveCanSave, expandsHorizontally: true))
        .allowsHitTesting(effectiveCanSave)
        .accessibilityIdentifier("AddSet.BottomSave")
    }

    private var exercisePickerRow: some View {
        HStack(spacing: MarbleLayout.rowSpacing) {
            Text("Exercise")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Spacer()

            if let exercise = selectedExerciseSnapshot {
                HStack(spacing: MarbleSpacing.xs) {
                    ExerciseIconView(icon: exercise.displayIcon, fontSize: 18, frameSize: 24)
                    Text(exercise.name)
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            } else {
                Text("Select")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .padding(.vertical, MarbleSpacing.s)
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
            weight = exercise.displayedWeightInput(fromStoredWeight: lastEntry.weight)
            weightUnit = lastEntry.weightUnit
            addedLoad = exercise.metrics.weightIsRequired || lastEntry.weight != nil
            if exercise.metrics.usesReps {
                if exercise.metrics.reps == .required {
                    reps = lastEntry.reps.map { clampReps($0) } ?? defaultRepsValue
                    logReps = true
                } else {
                    reps = lastEntry.reps.map { clampReps($0) }
                    logReps = lastEntry.reps != nil
                }
            } else {
                reps = nil
                logReps = false
            }
            if exercise.metrics.distance == .required {
                distance = lastEntry.distance ?? 100
                distanceUnit = lastEntry.distanceUnit
                logDistance = true
            } else if exercise.metrics.distance == .optional {
                distance = lastEntry.distance
                distanceUnit = lastEntry.distanceUnit
                logDistance = lastEntry.distance != nil
            } else {
                distance = nil
                distanceUnit = exercise.preferredDistanceUnit
                logDistance = false
            }
            if exercise.metrics.durationSeconds == .required {
                durationSeconds = lastEntry.durationSeconds ?? 60
                logDuration = true
            } else if exercise.metrics.durationSeconds == .optional {
                durationSeconds = lastEntry.durationSeconds
                logDuration = lastEntry.durationSeconds != nil
            } else {
                durationSeconds = nil
                logDuration = false
            }
            difficulty = lastEntry.difficulty
            restAfterSeconds = lastEntry.restAfterSeconds
            return
        }
        weight = nil
        addedLoad = exercise.metrics.weightIsRequired
        reps = exercise.metrics.repsIsRequired ? defaultRepsValue : nil
        logReps = exercise.metrics.repsIsRequired
        distance = exercise.metrics.distanceIsRequired ? 100 : nil
        distanceUnit = exercise.preferredDistanceUnit
        logDistance = exercise.metrics.distanceIsRequired
        durationSeconds = exercise.metrics.durationIsRequired ? 60 : nil
        logDuration = exercise.metrics.durationIsRequired
        difficulty = 8
        restAfterSeconds = exercise.defaultRestSeconds
    }

    private func save() {
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
        let resolvedReps: Int? = {
            if metrics.reps == .optional, !logReps {
                return nil
            }
            return metrics.usesReps ? reps : nil
        }()
        let resolvedDistance: Double? = {
            if metrics.distance == .optional, !logDistance {
                return nil
            }
            return metrics.usesDistance ? distance : nil
        }()
        let resolvedDurationSeconds: Int? = {
            if metrics.durationSeconds == .optional, !logDuration {
                return nil
            }
            return metrics.usesDuration ? durationSeconds : nil
        }()

        let now = AppEnvironment.now
        let entry = SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: exercise.storedWeight(from: resolvedWeight),
            weightUnit: weightUnit,
            reps: resolvedReps,
            distance: resolvedDistance,
            distanceUnit: distanceUnit,
            durationSeconds: resolvedDurationSeconds,
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

        closeSheet()
    }

    private func closeSheet() {
        quickLog.isPresentingAddSet = false
        isPresented = false
    }

    private func dismissKeyboard() {
        MarbleKeyboard.dismiss()
    }

    private func clampReps(_ value: Int) -> Int {
        min(max(value, repsRange.lowerBound), repsRange.upperBound)
    }

    private func shouldCaptureWeight(for metrics: ExerciseMetricsProfile) -> Bool {
        metrics.weightIsRequired || (metrics.weight == .optional && addedLoad)
    }

    private func shouldCaptureReps(for metrics: ExerciseMetricsProfile) -> Bool {
        metrics.repsIsRequired || (metrics.reps == .optional && logReps)
    }

    private func shouldCaptureDistance(for metrics: ExerciseMetricsProfile) -> Bool {
        metrics.distanceIsRequired || (metrics.distance == .optional && logDistance)
    }

    private func shouldCaptureDuration(for metrics: ExerciseMetricsProfile) -> Bool {
        metrics.durationIsRequired || (metrics.durationSeconds == .optional && logDuration)
    }
}

private extension AddSetView {
    struct ExerciseSnapshot: Equatable {
        let id: UUID
        let name: String
        let category: ExerciseCategory
        let displayIcon: ExerciseDisplayIcon
        let metrics: ExerciseMetricsProfile
        let resistanceTrackingStyle: ResistanceTrackingStyle
        let preferredDistanceUnit: DistanceUnit
        let defaultRestSeconds: Int

        init(_ exercise: Exercise) {
            id = exercise.id
            name = exercise.name
            category = exercise.category
            displayIcon = exercise.displayIcon
            metrics = exercise.metrics
            resistanceTrackingStyle = exercise.resistanceTrackingStyle
            preferredDistanceUnit = exercise.preferredDistanceUnit
            defaultRestSeconds = exercise.defaultRestSeconds
        }

        var weightInputTitle: String {
            resistanceTrackingStyle.fieldTitle
        }

        var weightInputHelperText: String {
            resistanceTrackingStyle.loggerHelperText
        }

        func displayedWeightInput(fromStoredWeight storedWeight: Double?) -> Double? {
            resistanceTrackingStyle.inputWeight(from: storedWeight)
        }

        func storedWeight(from inputWeight: Double?) -> Double? {
            resistanceTrackingStyle.storedWeight(from: inputWeight)
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

struct LastTimeMetric: Hashable {
    let label: String
    let value: String
}

struct LastTimeContent {
    let metrics: [LastTimeMetric]
    let loggedAtText: String?
    let emptyText: String?
    let accessibilityLabel: String
    let hasHistory: Bool
}

struct LastTimeCardView: View {
    let content: LastTimeContent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            if content.hasHistory {
                ViewThatFits(in: .horizontal) {
                    metricColumns
                    metricStack
                }

                if let loggedAtText = content.loggedAtText {
                    Text(loggedAtText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            } else if let emptyText = content.emptyText {
                Text(emptyText)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                        .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private var metricColumns: some View {
        HStack(alignment: .top, spacing: MarbleSpacing.m) {
            ForEach(content.metrics, id: \.label) { metric in
                metricCell(metric)
            }
        }
    }

    private var metricStack: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            ForEach(content.metrics, id: \.label) { metric in
                metricCell(metric)
            }
        }
    }

    private func metricCell(_ metric: LastTimeMetric) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(metric.label)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Text(metric.value)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
