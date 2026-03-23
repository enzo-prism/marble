import SwiftUI
import SwiftData

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    let exercise: Exercise?
    let initialName: String
    let onSave: ((Exercise) -> Void)?

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
    @State private var showSaveError = false
    @State private var didInitialize = false

    init(
        exercise: Exercise?,
        initialName: String = "",
        onSave: ((Exercise) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.initialName = initialName
        self.onSave = onSave
    }

    var body: some View {
        List {
            Section {
                Text(introText)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .padding(.vertical, MarbleSpacing.xs)
                    .accessibilityIdentifier("ExerciseEditor.Intro")
            }

            Section {
                editorFieldBlock(
                    title: "Exercise name",
                    description: "Use the name you'll want to search for and recognize instantly while logging."
                ) {
                    TextField("e.g. Bench Press", text: $name)
                        .focused($focusedField, equals: .name)
                        .marbleFieldStyle(nameValidationState)
                        .accessibilityIdentifier("ExerciseEditor.Name")
                }

                editorFieldBlock(
                    title: "Category",
                    description: "This keeps the exercise grouped correctly in the picker and sets the default system icon when you're not using a custom emoji."
                ) {
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .accessibilityIdentifier("ExerciseEditor.Category")
                }

                editorFieldBlock(
                    title: "Exercise icon",
                    description: "Use the category icon or pick one emoji that makes this exercise instantly recognizable."
                ) {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                        HStack(spacing: MarbleSpacing.s) {
                            ExerciseIconView(icon: draftDisplayIcon, fontSize: 28, frameSize: 44)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                                Text(iconSource == .emoji ? "Custom emoji icon" : "Category icon")
                                    .font(MarbleTypography.rowTitle)
                                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                                Text(iconPreviewDescription)
                                    .font(MarbleTypography.caption)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("ExerciseEditor.IconPreview")

                        Picker("Icon style", selection: $iconSource) {
                            ForEach(ExerciseIconSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Theme.dividerColor(for: colorScheme))
                        .accessibilityIdentifier("ExerciseEditor.IconMode")

                        if iconSource == .emoji {
                            TextField("e.g. 💪", text: $customIconEmoji)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .marbleFieldStyle(emojiValidationState)
                                .accessibilityIdentifier("ExerciseEditor.CustomEmoji")

                            Text("Use one emoji. If you paste several, Marble keeps the first valid one.")
                                .font(MarbleTypography.caption)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: MarbleSpacing.xs) {
                                    ForEach(Array(category.emojiSuggestions.enumerated()), id: \.offset) { index, emoji in
                                        Button {
                                            selectSuggestedEmoji(emoji)
                                        } label: {
                                            Text(emoji)
                                                .font(.system(size: 24))
                                                .frame(minWidth: 44, minHeight: 44)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                                        .fill(Theme.backgroundColor(for: colorScheme))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                                        .stroke(
                                                            resolvedCustomIconEmoji == emoji
                                                                ? Theme.primaryTextColor(for: colorScheme)
                                                                : Theme.dividerColor(for: colorScheme),
                                                            lineWidth: 1
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .simultaneousGesture(TapGesture().onEnded {
                                            selectSuggestedEmoji(emoji)
                                        })
                                        .accessibilityIdentifier("ExerciseEditor.EmojiSuggestion.\(index)")
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                }

                editorFieldBlock(
                    title: "Favorites",
                    description: "Favorites float up in the exercise picker so repeat logging is faster."
                ) {
                    Toggle("Show in favorites", isOn: $isFavorite)
                        .tint(Theme.dividerColor(for: colorScheme))
                        .accessibilityIdentifier("ExerciseEditor.Favorite")
                }
            } header: {
                SectionHeaderView(title: "Basics")
            }

            Section {
                metricRequirementGuideCard
                    .accessibilityIdentifier("ExerciseEditor.RequirementGuide")

                editorCard {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                        Text("Start from a common setup")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text("Start with the closest mold for this exercise, then fine-tune any field below.")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        LazyVGrid(columns: templateColumns, spacing: MarbleSpacing.s) {
                            ForEach(ExerciseLoggingTemplate.allCases) { template in
                                Button {
                                    applyTemplateSelection(template)
                                } label: {
                                    ExerciseTemplateCard(
                                        template: template,
                                        isSelected: selectedTemplate == template
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    applyTemplateSelection(template)
                                })
                                .accessibilityIdentifier("ExerciseEditor.Template.\(template.id)")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("ExerciseEditor.Templates")

                ForEach(ExerciseMetricKind.allCases) { kind in
                    metricConfigurationCard(kind: kind, selection: requirementBinding(for: kind))
                        .accessibilityIdentifier("ExerciseEditor.Metric.\(kind.id)")
                }

                if !validationMessages.isEmpty {
                    editorCard {
                        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                            Text(exercise == nil ? "Finish setup" : "Fix before saving")
                                .font(MarbleTypography.rowTitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                            ForEach(validationMessages, id: \.self) { message in
                                HStack(alignment: .top, spacing: MarbleSpacing.xs) {
                                    Text("•")
                                        .font(MarbleTypography.rowSubtitle)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    Text(message)
                                        .font(MarbleTypography.rowSubtitle)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("ExerciseEditor.Validation")
                }
            } header: {
                SectionHeaderView(title: "How You Log It")
            }

            Section {
                editorCard {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                        Text(metricsProfile.previewTitle)
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                        Text(metricsProfile.previewDescription)
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        Divider()

                        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                            Text("Exercise summary")
                                .font(MarbleTypography.smallLabel)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            Text(previewSummaryText)
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        }

                        if !previewBehaviorNotes.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                                Text("How Marble will interpret your logs")
                                    .font(MarbleTypography.smallLabel)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                ForEach(previewBehaviorNotes, id: \.self) { note in
                                    Text(note)
                                        .font(MarbleTypography.rowSubtitle)
                                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("ExerciseEditor.Preview")
            } header: {
                SectionHeaderView(title: "Logging Preview")
            }

            if existingHistoryCount > 0 {
                Section {
                    editorCard {
                        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                            Text("\(existingHistoryCount) logged \(existingHistoryCount == 1 ? "set" : "sets") already use this exercise")
                                .font(MarbleTypography.rowTitle)
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            Text("Changing the logging setup updates how those saved sets are interpreted across the app. Double-check metric changes before saving.")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                    .accessibilityIdentifier("ExerciseEditor.HistoryImpact")
                } header: {
                    SectionHeaderView(title: "History Impact")
                }
            }

            Section {
                editorCard {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                        Text("Default rest")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text("This prefills the rest timer whenever you start a new log for this exercise.")
                            .font(MarbleTypography.rowSubtitle)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        RestPicker(restSeconds: $defaultRestSeconds)
                            .accessibilityIdentifier("ExerciseEditor.DefaultRest")
                    }
                }
            } header: {
                SectionHeaderView(title: "Defaults")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
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
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't save this exercise. Please try again.")
        }
    }

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

    private var iconPreviewDescription: String {
        if iconSource == .emoji {
            return resolvedCustomIconEmoji == nil
                ? "Choose one emoji and Marble will use it everywhere this exercise appears."
                : "Your emoji will appear anywhere this exercise is shown."
        }
        return "Uses the \(category.displayName) system icon automatically until you switch to a custom emoji."
    }

    private var introText: String {
        if exercise == nil {
            return "Set this exercise up once so future logging is obvious, fast, and tailored to how you actually train."
        }
        return "Refine how this exercise behaves in the logger so future sets are easy to enter and easy to trust."
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

    private var previewSummaryText: String {
        let title = trimmedName.isEmpty ? "This exercise" : trimmedName
        return "\(title) · \(metricsProfile.summaryText(defaultRestSeconds: defaultRestSeconds, loadTrackingStyle: resistanceTrackingStyle, distanceUnit: preferredDistanceUnit))"
    }

    private var previewBehaviorNotes: [String] {
        var notes: [String] = []

        if metricsProfile.usesWeight {
            notes.append(resistanceTrackingStyle.editorDescription)
        }

        if metricsProfile.usesDistance {
            notes.append("Distance uses \(preferredDistanceUnit.title.lowercased()) by default when you log this exercise.")
        }

        if metricsProfile.usesDistance && metricsProfile.usesDuration {
            notes.append("This setup works well for sprints and intervals where both distance and time matter.")
        }

        return notes
    }

    private var nameValidationState: MarbleFieldState {
        (trimmedName.isEmpty || duplicateExercise != nil) ? .error : .normal
    }

    private var emojiValidationState: MarbleFieldState {
        iconSource == .emoji && resolvedCustomIconEmoji == nil ? .error : .normal
    }

    private var templateColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: MarbleSpacing.s),
            GridItem(.flexible(), spacing: MarbleSpacing.s)
        ]
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

    private func configureInitialState() {
        if let exercise {
            load(from: exercise)
        } else {
            name = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                focusedField = .name
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

    private func editorFieldBlock<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text(title)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Text(description)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

            content()
        }
        .padding(.vertical, MarbleSpacing.xs)
    }

    private var metricRequirementGuideCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text("Choose what each set should capture")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text("Off means the logger never shows that field. Optional adds a per-set toggle. Required shows it every time.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    requirementGuideRow(
                        title: "Off",
                        description: "Hide this field entirely for the exercise."
                    )
                    requirementGuideRow(
                        title: "Optional",
                        description: "Show a toggle in the logger so you can include it only when needed."
                    )
                    requirementGuideRow(
                        title: "Required",
                        description: "Ask for it on every set so logging stays consistent."
                    )
                }
            }
        }
    }

    private func requirementGuideRow(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(title)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text(description)
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricConfigurationCard(kind: ExerciseMetricKind, selection: Binding<MetricRequirement>) -> some View {
        editorCard {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text(kind.editorTitle)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(kind.editorDescription)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Picker(kind.editorTitle, selection: selection) {
                    Text("Off").tag(MetricRequirement.none)
                    Text("Optional").tag(MetricRequirement.optional)
                    Text("Required").tag(MetricRequirement.required)
                }
                .pickerStyle(.segmented)
                .tint(Theme.dividerColor(for: colorScheme))

                Text(kind.helperText(for: selection.wrappedValue))
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                if kind == .weight, selection.wrappedValue != .none {
                    Divider()

                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text("How you enter load")
                            .font(MarbleTypography.smallLabel)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        Picker("How you enter load", selection: $resistanceTrackingStyle) {
                            ForEach(ResistanceTrackingStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Theme.dividerColor(for: colorScheme))
                        .accessibilityIdentifier("ExerciseEditor.WeightTrackingStyle")

                        Text(resistanceTrackingStyle.editorDescription)
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if kind == .distance, selection.wrappedValue != .none {
                    Divider()

                    VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                        Text("Distance unit")
                            .font(MarbleTypography.smallLabel)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                        Picker("Distance unit", selection: $preferredDistanceUnit) {
                            ForEach(DistanceUnit.allCases) { unit in
                                Text(unit.symbol.uppercased()).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.dividerColor(for: colorScheme))
                        .accessibilityIdentifier("ExerciseEditor.DistanceUnit")

                        Text("Marble will default this exercise to \(preferredDistanceUnit.title.lowercased()) when you log each set.")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            content()
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .fill(Theme.chipFillColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
        )
        .listRowInsets(MarbleLayout.rowInsets)
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
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
        dismiss()
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
                return "Weight"
            case .dualDumbbell:
                return "2 Dumbbells"
            case .bodyweight:
                return "Bodyweight"
            case .weightedBodyweight:
                return "Weighted BW"
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
                return "Single load + reps"
            case .dualDumbbell:
                return "One dumbbell + reps"
            case .bodyweight:
                return "Reps only"
            case .weightedBodyweight:
                return "Reps, optional load"
            case .sprint:
                return "Distance + time"
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
            switch self {
            case .sprint:
                return .meters
            default:
                return .meters
            }
        }
    }
}

private struct ExerciseTemplateCard: View {
    let template: ExerciseEditorView.ExerciseLoggingTemplate
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            Text(template.title)
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text(template.subtitle)
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MarbleSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .fill(Theme.backgroundColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(
                    isSelected ? Theme.primaryTextColor(for: colorScheme) : Theme.dividerColor(for: colorScheme),
                    lineWidth: 1
                )
        )
    }
}
