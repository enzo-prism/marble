import Foundation

enum ExerciseKind: String, CaseIterable, Identifiable, Hashable {
    case strength
    case dualDumbbell
    case bodyweight
    case weightedBodyweight
    case run
    case sprint
    case plyometric
    case timed
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Strength"
        case .dualDumbbell: "Two Dumbbells"
        case .bodyweight: "Bodyweight"
        case .weightedBodyweight: "Weighted Bodyweight"
        case .run: "Run"
        case .sprint: "Sprint"
        case .plyometric: "Jump / Plyometric"
        case .timed: "Timed"
        case .custom: "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: "Weight and reps"
        case .dualDumbbell: "One dumbbell weight and reps"
        case .bodyweight: "Reps only"
        case .weightedBodyweight: "Reps with optional added weight"
        case .run: "Distance and time"
        case .sprint: "Distance, repeats, target time, and recovery"
        case .plyometric: "Explosive reps"
        case .timed: "Time only"
        case .custom: "Choose every field yourself"
        }
    }

    var symbolName: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .dualDumbbell: "dumbbell"
        case .bodyweight: "figure.core.training"
        case .weightedBodyweight: "figure.strengthtraining.traditional"
        case .run: "figure.run"
        case .sprint: "bolt.fill"
        case .plyometric: "figure.jumprope"
        case .timed: "timer"
        case .custom: "slider.horizontal.3"
        }
    }

    var defaultMetrics: ExerciseMetricsProfile {
        switch self {
        case .strength, .dualDumbbell:
            .weightAndRepsRequired
        case .bodyweight, .plyometric:
            .repsOnlyRequired
        case .weightedBodyweight:
            ExerciseMetricsProfile(weight: .optional, reps: .required, distance: .none, durationSeconds: .none)
        case .run, .sprint:
            .distanceAndDurationRequired
        case .timed:
            .durationOnlyRequired
        case .custom:
            .repsOnlyRequired
        }
    }

    var defaultResistanceStyle: ResistanceTrackingStyle {
        self == .dualDumbbell ? .singleDumbbellPair : .totalLoad
    }

    var defaultDistanceUnit: DistanceUnit {
        self == .run ? .kilometers : .meters
    }

    var impliedCategory: ExerciseCategory? {
        switch self {
        case .run, .sprint: .run
        case .plyometric: .power
        default: nil
        }
    }

    static func infer(
        name: String = "",
        metrics: ExerciseMetricsProfile,
        resistanceStyle: ResistanceTrackingStyle,
        category: ExerciseCategory,
        hasSprintPrescription: Bool
    ) -> ExerciseKind {
        if hasSprintPrescription || (
            metrics == .distanceAndDurationRequired &&
            name.localizedCaseInsensitiveContains("sprint")
        ) { return .sprint }
        if metrics == .durationOnlyRequired { return .timed }
        if metrics == .distanceAndDurationRequired { return .run }
        if metrics == .weightAndRepsRequired {
            return resistanceStyle == .singleDumbbellPair ? .dualDumbbell : .strength
        }
        if metrics == ExerciseMetricsProfile(weight: .optional, reps: .required, distance: .none, durationSeconds: .none) {
            return .weightedBodyweight
        }
        if metrics == .repsOnlyRequired {
            switch category {
            case .power, .legs, .quads, .hamstrings, .calves:
                return .plyometric
            default:
                return .bodyweight
            }
        }
        return .custom
    }
}

struct ExerciseEditorDraft: Equatable {
    var name: String
    var kind: ExerciseKind
    var category: ExerciseCategory
    var iconSource: ExerciseIconSource
    var customIconEmoji: String
    var resistanceTrackingStyle: ResistanceTrackingStyle
    var metrics: ExerciseMetricsProfile
    var preferredDistanceUnit: DistanceUnit
    var defaultRestSeconds: Int
    var isFavorite: Bool
    var sprintDistance: Double?
    var sprintRepetitionCount: Int
    var sprintTargetMode: SprintTargetMode
    var sprintTargetSeconds: Int?
    var sprintTargetLowerSeconds: Int?
    var sprintTargetUpperSeconds: Int?

    static func new(initialName: String = "") -> ExerciseEditorDraft {
        ExerciseEditorDraft(
            name: initialName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .strength,
            category: .other,
            iconSource: .category,
            customIconEmoji: "",
            resistanceTrackingStyle: .totalLoad,
            metrics: .weightAndRepsRequired,
            preferredDistanceUnit: .meters,
            defaultRestSeconds: 60,
            isFavorite: false,
            sprintDistance: 60,
            sprintRepetitionCount: 4,
            sprintTargetMode: .time,
            sprintTargetSeconds: 8,
            sprintTargetLowerSeconds: 19,
            sprintTargetUpperSeconds: 21
        )
    }

    init(exercise: Exercise, prescription: SprintPrescription?) {
        name = exercise.name
        category = exercise.category
        customIconEmoji = exercise.sanitizedCustomIconEmoji ?? ""
        iconSource = exercise.sanitizedCustomIconEmoji == nil ? .category : .emoji
        resistanceTrackingStyle = exercise.resistanceTrackingStyle
        metrics = exercise.metrics
        preferredDistanceUnit = exercise.preferredDistanceUnit
        defaultRestSeconds = exercise.defaultRestSeconds
        isFavorite = exercise.isFavorite
        sprintDistance = prescription?.distance ?? 60
        sprintRepetitionCount = prescription?.repetitionCount ?? 4
        sprintTargetMode = prescription?.targetMode ?? .time
        sprintTargetSeconds = prescription?.targetLowerSeconds ?? 8
        sprintTargetLowerSeconds = prescription?.targetLowerSeconds ?? 19
        sprintTargetUpperSeconds = prescription?.targetUpperSeconds ?? 21
        kind = ExerciseKind.infer(
            name: exercise.name,
            metrics: exercise.metrics,
            resistanceStyle: exercise.resistanceTrackingStyle,
            category: exercise.category,
            hasSprintPrescription: prescription != nil
        )
    }

    private init(
        name: String,
        kind: ExerciseKind,
        category: ExerciseCategory,
        iconSource: ExerciseIconSource,
        customIconEmoji: String,
        resistanceTrackingStyle: ResistanceTrackingStyle,
        metrics: ExerciseMetricsProfile,
        preferredDistanceUnit: DistanceUnit,
        defaultRestSeconds: Int,
        isFavorite: Bool,
        sprintDistance: Double?,
        sprintRepetitionCount: Int,
        sprintTargetMode: SprintTargetMode,
        sprintTargetSeconds: Int?,
        sprintTargetLowerSeconds: Int?,
        sprintTargetUpperSeconds: Int?
    ) {
        self.name = name
        self.kind = kind
        self.category = category
        self.iconSource = iconSource
        self.customIconEmoji = customIconEmoji
        self.resistanceTrackingStyle = resistanceTrackingStyle
        self.metrics = metrics
        self.preferredDistanceUnit = preferredDistanceUnit
        self.defaultRestSeconds = defaultRestSeconds
        self.isFavorite = isFavorite
        self.sprintDistance = sprintDistance
        self.sprintRepetitionCount = sprintRepetitionCount
        self.sprintTargetMode = sprintTargetMode
        self.sprintTargetSeconds = sprintTargetSeconds
        self.sprintTargetLowerSeconds = sprintTargetLowerSeconds
        self.sprintTargetUpperSeconds = sprintTargetUpperSeconds
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedCustomIconEmoji: String? {
        customIconEmoji.firstExerciseEmoji
    }

    var usesSprintPrescription: Bool { kind == .sprint }

    mutating func apply(_ newKind: ExerciseKind) {
        kind = newKind
        guard newKind != .custom else {
            if !metrics.hasAnyMetric { metrics = .repsOnlyRequired }
            return
        }
        metrics = newKind.defaultMetrics
        resistanceTrackingStyle = newKind.defaultResistanceStyle
        preferredDistanceUnit = newKind.defaultDistanceUnit
        if let impliedCategory = newKind.impliedCategory {
            category = impliedCategory
        } else if newKind != .custom, category == .run || category == .power {
            category = .other
        }
        if newKind == .sprint {
            sprintDistance = sprintDistance ?? 60
            sprintRepetitionCount = max(1, sprintRepetitionCount)
        }
    }

    func nameError(existingExercises: [Exercise], excluding exerciseID: UUID?) -> String? {
        guard !trimmedName.isEmpty else { return "Enter an exercise name." }
        if let duplicate = existingExercises.first(where: {
            $0.id != exerciseID &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            return "\"\(duplicate.name)\" already exists."
        }
        return nil
    }

    var trackingError: String? {
        metrics.hasAnyMetric ? nil : "Choose at least one field to track."
    }

    var iconError: String? {
        iconSource == .emoji && resolvedCustomIconEmoji == nil ? "Choose one emoji or use the category icon." : nil
    }

    var sprintErrors: [String] {
        guard usesSprintPrescription else { return [] }
        var errors: [String] = []
        if !metrics.distanceIsRequired || !metrics.durationIsRequired {
            errors.append("Sprints need distance and time on every rep.")
        }
        if (sprintDistance ?? 0) <= 0 { errors.append("Enter a sprint distance.") }
        if !(1...50).contains(sprintRepetitionCount) { errors.append("Choose 1–50 repetitions.") }
        switch sprintTargetMode {
        case .time:
            if (sprintTargetSeconds ?? 0) <= 0 { errors.append("Enter a target time.") }
        case .range:
            let lower = sprintTargetLowerSeconds ?? 0
            let upper = sprintTargetUpperSeconds ?? 0
            if lower <= 0 { errors.append("Enter the fast end of the target range.") }
            if upper < lower { errors.append("The slow end must be equal to or slower than the fast end.") }
        }
        return errors
    }

    func validationErrors(existingExercises: [Exercise], excluding exerciseID: UUID?) -> [String] {
        [
            nameError(existingExercises: existingExercises, excluding: exerciseID),
            trackingError,
            iconError
        ].compactMap { $0 } + sprintErrors
    }

    func changesHistoricalInterpretation(from exercise: Exercise) -> Bool {
        metrics != exercise.metrics || resistanceTrackingStyle != exercise.resistanceTrackingStyle
    }

    func changesPlannedWorkoutBehavior(from original: ExerciseEditorDraft) -> Bool {
        metrics != original.metrics ||
        resistanceTrackingStyle != original.resistanceTrackingStyle ||
        preferredDistanceUnit != original.preferredDistanceUnit ||
        defaultRestSeconds != original.defaultRestSeconds ||
        usesSprintPrescription != original.usesSprintPrescription ||
        (usesSprintPrescription && (
            sprintDistance != original.sprintDistance ||
            sprintRepetitionCount != original.sprintRepetitionCount ||
            sprintTargetMode != original.sprintTargetMode ||
            sprintTargetSeconds != original.sprintTargetSeconds ||
            sprintTargetLowerSeconds != original.sprintTargetLowerSeconds ||
            sprintTargetUpperSeconds != original.sprintTargetUpperSeconds
        ))
    }
}
