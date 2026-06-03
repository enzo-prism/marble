import SwiftUI
import SwiftData

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    let exercise: Exercise?
    let initialName: String
    let onSave: ((Exercise) -> Void)?
    let dismissAfterSave: Bool

    @FocusState private var focusedField: Field?

    @State private var name: String = ""
    @State private var category: ExerciseCategory = .other
    @State private var iconSource: ExerciseIconSource = .category
    @State private var customIconEmoji: String = ""
    @State private var resistanceTrackingStyle: ResistanceTrackingStyle = .totalLoad
    @State private var weightRequirement: MetricRequirement = .none
    @State private var repsRequirement: MetricRequirement = .none
    @State private var distanceRequirement: MetricRequirement = .none
    @State private var preferredDistanceUnit: DistanceUnit = .meters
    @State private var durationRequirement: MetricRequirement = .none
    @State private var defaultRestSeconds: Int = 60
    @State private var isFavorite: Bool = false
    @State private var showCustomMetrics = false
    @State private var showSaveError = false
    @State private var didInitialize = false

    init(
        exercise: Exercise?,
        initialName: String = "",
        dismissAfterSave: Bool = true,
        onSave: ((Exercise) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.initialName = initialName
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
    }

    var body: some View {
        List {
            nameSection
            iconSection
            typeSection
            loggingDetailSection
            defaultsSection
            historySection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(exercise == nil ? "Create Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(!validationMessages.isEmpty)
                .accessibilityIdentifier("ExerciseEditor.Save")
            }
        }
        .onAppear {
            guard !didInitialize else { return }
            configureInitialState()
            didInitialize = true
        }
        .onChange(of: customIconEmoji) { _, newValue in
            let sanitized = newValue.firstExerciseEmoji ?? ""
            if sanitized != newValue {
                customIconEmoji = sanitized
            }
        }
        .onChange(of: iconSource) { _, _ in
            ensureDefaultEmojiSelection()
        }
        .onChange(of: category) { _, _ in
            ensureDefaultEmojiSelection()
        }
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't save this exercise. Please try again.")
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Exercise name", text: $name)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .accessibilityIdentifier("ExerciseEditor.Name")

            Picker("Category", selection: $category) {
                ForEach(ExerciseCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .accessibilityIdentifier("ExerciseEditor.Category")
        } footer: {
            if let nameError {
                Text(nameError)
            } else {
                Text("Use the name you'll search for and recognize instantly while logging.")
            }
        }
    }

    private var iconSection: some View {
        Section {
            LabeledContent {
                ExerciseIconView(icon: draftDisplayIcon, fontSize: 26, frameSize: 36)
                    .accessibilityHidden(true)
            } label: {
                Text(iconSource == .emoji ? "Custom emoji" : "Category icon")
            }

            Picker("Icon style", selection: $iconSource) {
                ForEach(ExerciseIconSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ExerciseEditor.IconMode")

            if iconSource == .emoji {
                TextField("Emoji", text: $customIconEmoji)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ExerciseEditor.CustomEmoji")

                emojiSuggestionRow
            }
        } header: {
            Text("Icon")
        } footer: {
            Text(iconFooter)
        }
    }

    private var emojiSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MarbleSpacing.xs) {
                ForEach(Array(category.emojiSuggestions.enumerated()), id: \.offset) { index, emoji in
                    Button {
                        selectSuggestedEmoji(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                    .fill(.quaternary.opacity(resolvedCustomIconEmoji == emoji ? 0.9 : 0.4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                    .strokeBorder(.tint, lineWidth: resolvedCustomIconEmoji == emoji ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ExerciseEditor.EmojiSuggestion.\(index)")
                    .accessibilityLabel("Emoji option \(index + 1)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var typeSection: some View {
        Section {
            ForEach(ExerciseLoggingTemplate.allCases) { template in
                Button {
                    applyTemplateSelection(template)
                } label: {
                    HStack(spacing: MarbleSpacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .foregroundStyle(.primary)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: MarbleSpacing.s)
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .opacity(selectedTemplate == template ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ExerciseEditor.Template.\(template.id)")
                .accessibilityAddTraits(selectedTemplate == template ? [.isSelected] : [])
            }
        } header: {
            Text("Type")
        } footer: {
            Text(typeFooter)
        }
    }

    @ViewBuilder
    private var loggingDetailSection: some View {
        Section {
            if metricsProfile.usesWeight {
                Picker("Load entry", selection: $resistanceTrackingStyle) {
                    ForEach(ResistanceTrackingStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("ExerciseEditor.WeightTrackingStyle")
            }

            if metricsProfile.usesDistance {
                Picker("Distance unit", selection: $preferredDistanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("ExerciseEditor.DistanceUnit")
            }

            DisclosureGroup(isExpanded: $showCustomMetrics) {
                ForEach(ExerciseMetricKind.allCases) { kind in
                    Picker(kind.editorTitle, selection: requirementBinding(for: kind)) {
                        Text("Off").tag(MetricRequirement.none)
                        Text("Optional").tag(MetricRequirement.optional)
                        Text("Required").tag(MetricRequirement.required)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("ExerciseEditor.Metric.\(kind.id)")
                }
            } label: {
                LabeledContent("Customize metrics") {
                    Text(selectedTemplate == nil ? "Custom" : "")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Logging")
        } footer: {
            Text("Off hides the field. Optional adds a per-set toggle. Required asks for it every time.")
        }
    }

    private var defaultsSection: some View {
        Section {
            RestPicker(restSeconds: $defaultRestSeconds)
                .accessibilityIdentifier("ExerciseEditor.DefaultRest")

            Toggle("Favorite", isOn: $isFavorite)
                .tint(Theme.toggleOnColor)
                .accessibilityIdentifier("ExerciseEditor.Favorite")
        } header: {
            Text("Defaults")
        } footer: {
            Text("Default rest prefills the timer for new logs. Favorites float to the top of the picker.")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if existingHistoryCount > 0 {
            Section {
                Text("\(existingHistoryCount) logged \(existingHistoryCount == 1 ? "set" : "sets") use this exercise. Changing the logging setup updates how those saved sets are interpreted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ExerciseEditor.HistoryImpact")
            } header: {
                Text("History")
            }
        }
    }

    // MARK: - Derived state

    private var metricsProfile: ExerciseMetricsProfile {
        ExerciseMetricsProfile(
            weight: weightRequirement,
            reps: repsRequirement,
            distance: distanceRequirement,
            durationSeconds: durationRequirement
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedCustomIconEmoji: String? {
        customIconEmoji.firstExerciseEmoji
    }

    private var draftDisplayIcon: ExerciseDisplayIcon {
        if iconSource == .emoji, let emoji = resolvedCustomIconEmoji {
            return .emoji(emoji)
        }
        return .symbol(category.symbolName)
    }

    private var iconFooter: String {
        if iconSource == .emoji {
            return resolvedCustomIconEmoji == nil
                ? "Choose one emoji. If you paste several, Marble keeps the first valid one."
                : "Your emoji appears everywhere this exercise is shown."
        }
        return "Uses the \(category.displayName) system icon until you switch to a custom emoji."
    }

    private var typeFooter: String {
        if selectedTemplate == nil {
            return "Custom setup. Adjust each metric under Logging below."
        }
        return metricsProfile.previewTitle
    }

    private var existingHistoryCount: Int {
        guard let exerciseID = exercise?.id else { return 0 }
        return entries.filter { $0.exercise.id == exerciseID }.count
    }

    private var duplicateExercise: Exercise? {
        exercises.first { candidate in
            candidate.id != exercise?.id &&
            candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var nameError: String? {
        if trimmedName.isEmpty {
            return nil
        }
        if let duplicateExercise {
            return "\"\(duplicateExercise.name)\" already exists. Edit that exercise or choose a more specific name."
        }
        return nil
    }

    private var validationMessages: [String] {
        var messages: [String] = []

        if trimmedName.isEmpty {
            messages.append("Add a clear exercise name so it's easy to find later.")
        }

        if let duplicateExercise {
            messages.append("\"\(duplicateExercise.name)\" already exists. Edit that exercise instead or choose a more specific name.")
        }

        if iconSource == .emoji && resolvedCustomIconEmoji == nil {
            messages.append("Choose one emoji for the custom icon, or switch back to the category icon.")
        }

        if !metricsProfile.hasAnyMetric {
            messages.append("Turn on at least one metric so this exercise has something meaningful to log.")
        }

        return messages
    }

    private var selectedTemplate: ExerciseLoggingTemplate? {
        if metricsProfile == .durationOnlyRequired {
            return .timed
        }

        if metricsProfile == .distanceAndDurationRequired {
            return .sprint
        }

        if metricsProfile == .weightAndRepsRequired {
            return resistanceTrackingStyle == .singleDumbbellPair ? .dualDumbbell : .strength
        }

        if metricsProfile == ExerciseMetricsProfile(weight: .optional, reps: .required, distance: .none, durationSeconds: .none) {
            return .weightedBodyweight
        }

        if metricsProfile == .repsOnlyRequired {
            switch category {
            case .power, .legs, .quads, .hamstrings, .calves:
                return .plyometric
            default:
                return .bodyweight
            }
        }

        return nil
    }

    private func requirementBinding(for kind: ExerciseMetricKind) -> Binding<MetricRequirement> {
        Binding(
            get: { metricsProfile.requirement(for: kind) },
            set: { newValue in
                switch kind {
                case .weight:
                    weightRequirement = newValue
                case .reps:
                    repsRequirement = newValue
                case .distance:
                    distanceRequirement = newValue
                case .duration:
                    durationRequirement = newValue
                }
            }
        )
    }

    // MARK: - Actions

    private func configureInitialState() {
        if let exercise {
            load(from: exercise)
        } else {
            name = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only raise the keyboard for a genuinely blank create. When a name is
            // pre-filled (e.g. created from search) keep focus clear so the type
            // rows just below stay fully tappable and we don't pop the keyboard
            // for nothing.
            if name.isEmpty {
                DispatchQueue.main.async {
                    focusedField = .name
                }
            }
        }
    }

    private func apply(template: ExerciseLoggingTemplate) {
        weightRequirement = template.profile.weight
        repsRequirement = template.profile.reps
        distanceRequirement = template.profile.distance
        durationRequirement = template.profile.durationSeconds
        resistanceTrackingStyle = template.resistanceTrackingStyle
        preferredDistanceUnit = template.distanceUnit
    }

    private func applyTemplateSelection(_ template: ExerciseLoggingTemplate) {
        focusedField = nil
        apply(template: template)
    }

    private func selectSuggestedEmoji(_ emoji: String) {
        focusedField = nil
        customIconEmoji = emoji
    }

    private func ensureDefaultEmojiSelection() {
        guard iconSource == .emoji, resolvedCustomIconEmoji == nil else { return }
        customIconEmoji = category.emojiSuggestions.first ?? ""
    }

    private func load(from exercise: Exercise) {
        name = exercise.name
        category = exercise.category
        customIconEmoji = exercise.sanitizedCustomIconEmoji ?? ""
        iconSource = exercise.sanitizedCustomIconEmoji == nil ? .category : .emoji
        resistanceTrackingStyle = exercise.resistanceTrackingStyle
        weightRequirement = exercise.metrics.weight
        repsRequirement = exercise.metrics.reps
        distanceRequirement = exercise.metrics.distance
        preferredDistanceUnit = exercise.preferredDistanceUnit
        durationRequirement = exercise.metrics.durationSeconds
        defaultRestSeconds = exercise.defaultRestSeconds
        isFavorite = exercise.isFavorite
        showCustomMetrics = selectedTemplate == nil
    }

    private func save() {
        guard validationMessages.isEmpty else { return }

        let savedExercise: Exercise

        if let exercise {
            exercise.name = trimmedName
            exercise.category = category
            exercise.setCustomIconEmoji(iconSource == .emoji ? resolvedCustomIconEmoji : nil)
            exercise.setResistanceTrackingStyle(resistanceTrackingStyle)
            exercise.setPreferredDistanceUnit(preferredDistanceUnit)
            exercise.metrics = metricsProfile
            exercise.defaultRestSeconds = defaultRestSeconds
            exercise.isFavorite = isFavorite
            savedExercise = exercise
        } else {
            let newExercise = Exercise(
                name: trimmedName,
                category: category,
                customIconEmoji: iconSource == .emoji ? resolvedCustomIconEmoji : nil,
                resistanceTrackingStyle: resistanceTrackingStyle,
                preferredDistanceUnit: preferredDistanceUnit,
                metrics: metricsProfile,
                defaultRestSeconds: defaultRestSeconds,
                isFavorite: isFavorite
            )
            modelContext.insert(newExercise)
            savedExercise = newExercise
        }

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Save exercise failed: \(error)")
            #endif
            modelContext.rollback()
            showSaveError = true
            return
        }

        onSave?(savedExercise)
        if dismissAfterSave {
            dismiss()
        }
    }
}

fileprivate extension ExerciseEditorView {
    enum Field: Hashable {
        case name
    }

    enum ExerciseLoggingTemplate: String, CaseIterable, Identifiable {
        case strength
        case dualDumbbell
        case bodyweight
        case weightedBodyweight
        case sprint
        case plyometric
        case timed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .strength:
                return "Weighted"
            case .dualDumbbell:
                return "Dumbbell pair"
            case .bodyweight:
                return "Bodyweight"
            case .weightedBodyweight:
                return "Weighted bodyweight"
            case .sprint:
                return "Sprint"
            case .plyometric:
                return "Plyometric"
            case .timed:
                return "Timed"
            }
        }

        var subtitle: String {
            switch self {
            case .strength:
                return "Single load and reps"
            case .dualDumbbell:
                return "One dumbbell weight and reps"
            case .bodyweight:
                return "Reps only"
            case .weightedBodyweight:
                return "Reps with optional added load"
            case .sprint:
                return "Distance and time"
            case .plyometric:
                return "Explosive reps"
            case .timed:
                return "Duration only"
            }
        }

        var profile: ExerciseMetricsProfile {
            switch self {
            case .strength:
                return .weightAndRepsRequired
            case .dualDumbbell:
                return .weightAndRepsRequired
            case .bodyweight:
                return .repsOnlyRequired
            case .weightedBodyweight:
                return ExerciseMetricsProfile(weight: .optional, reps: .required, distance: .none, durationSeconds: .none)
            case .sprint:
                return .distanceAndDurationRequired
            case .plyometric:
                return .repsOnlyRequired
            case .timed:
                return .durationOnlyRequired
            }
        }

        var resistanceTrackingStyle: ResistanceTrackingStyle {
            switch self {
            case .dualDumbbell:
                return .singleDumbbellPair
            default:
                return .totalLoad
            }
        }

        var distanceUnit: DistanceUnit {
            .meters
        }
    }
}
