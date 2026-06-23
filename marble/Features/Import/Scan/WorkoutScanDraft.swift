import Foundation

/// A workout parsed from a photographed / scanned handwritten note, *before* the
/// user reviews it and commits it to the journal.
///
/// These are pure value types with no dependency on Vision, the on-device model,
/// SwiftData, or SwiftUI, so the parsing and mapping logic is fully unit-testable.
/// The flow is: image → OCR text → `ParsedWorkoutDraft` (this) → user review/edit →
/// `WorkoutScanImporter` → `SetEntry`s in the journal.
nonisolated struct ParsedWorkoutDraft: Equatable, Sendable {
    /// The session date written on the note, if one was recognized. `nil` means
    /// "use now" at import time.
    var performedAt: Date?
    /// A short human label (a header line on the note, or a default).
    var title: String
    var exercises: [ParsedExerciseDraft]

    init(
        performedAt: Date? = nil,
        title: String = "Scanned workout",
        exercises: [ParsedExerciseDraft] = []
    ) {
        self.performedAt = performedAt
        self.title = title
        self.exercises = exercises
    }

    /// Exercises that actually carry at least one set — the only ones worth importing.
    var importableExercises: [ParsedExerciseDraft] {
        exercises.filter { !$0.sets.isEmpty && !$0.trimmedName.isEmpty }
    }

    /// True when there is at least one set worth importing.
    var hasContent: Bool { !importableExercises.isEmpty }

    var totalSetCount: Int { importableExercises.reduce(0) { $0 + $1.sets.count } }
}

nonisolated struct ParsedExerciseDraft: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var sets: [ParsedSetDraft]

    init(id: UUID = UUID(), name: String, sets: [ParsedSetDraft] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Aggregate metrics profile across the exercise's sets: a metric is "used" when
    /// any set carries a value for it. This becomes the `ExerciseMetricsProfile` for a
    /// newly created `Exercise`, so a bodyweight movement (reps only) doesn't get
    /// mislabeled as requiring a weight, and a timed hold tracks only duration.
    var metricsProfile: ExerciseMetricsProfile {
        let usesWeight = sets.contains { $0.weight != nil }
        let usesReps = sets.contains { $0.reps != nil }
        let usesDistance = sets.contains { $0.distance != nil }
        let usesDuration = sets.contains { $0.durationSeconds != nil }
        // Guarantee at least one metric so the created exercise is never "empty";
        // default to reps, the most common bodyweight fallback.
        if !usesWeight && !usesReps && !usesDistance && !usesDuration {
            return .repsOnlyRequired
        }
        return ExerciseMetricsProfile(
            weight: usesWeight ? .required : .none,
            reps: usesReps ? .required : .none,
            distance: usesDistance ? .required : .none,
            durationSeconds: usesDuration ? .required : .none
        )
    }
}

nonisolated struct ParsedSetDraft: Equatable, Sendable, Identifiable {
    var id: UUID
    var weight: Double?
    var weightUnit: WeightUnit
    var reps: Int?
    /// Distance expressed in `distanceUnit` (matching how `SetEntry` stores it).
    var distance: Double?
    var distanceUnit: DistanceUnit
    var durationSeconds: Int?

    init(
        id: UUID = UUID(),
        weight: Double? = nil,
        weightUnit: WeightUnit = .lb,
        reps: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .meters,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.weight = weight
        self.weightUnit = weightUnit
        self.reps = reps
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.durationSeconds = durationSeconds
    }

    var hasAnyValue: Bool {
        weight != nil || reps != nil || distance != nil || durationSeconds != nil
    }
}
