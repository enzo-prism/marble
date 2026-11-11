import AppIntents
import Foundation
import SwiftData

// MARK: - Unit enum

/// `WeightUnit` as something Siri and the Shortcuts editor can offer.
///
/// Raw values match `WeightUnit` so the two can never drift, and so a saved
/// shortcut keeps meaning the same thing across releases.
nonisolated enum WeightUnitAppEnum: String, AppEnum, CaseIterable {
    case lb
    case kg

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Weight Unit" }

    static var caseDisplayRepresentations: [WeightUnitAppEnum: DisplayRepresentation] {
        [
            .lb: DisplayRepresentation(title: "Pounds", subtitle: "lb"),
            .kg: DisplayRepresentation(title: "Kilograms", subtitle: "kg")
        ]
    }

    var weightUnit: WeightUnit {
        switch self {
        case .lb: return .lb
        case .kg: return .kg
        }
    }

    init(_ unit: WeightUnit) {
        switch unit {
        case .lb: self = .lb
        case .kg: self = .kg
        }
    }
}

// MARK: - Intent

/// Logs one set of a named exercise, filling any gap from that exercise's history.
///
/// Every metric is optional so a spoken request can be as short as "log a set of
/// bench press in Marble" — the missing reps/weight/unit come from the most recent
/// set of the *same* exercise, which is the same idea as `LogLastSetAgainIntent`
/// but scoped to one movement instead of "whatever you did last".
#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct LogSetIntent: LiveActivityIntent, PredictableIntent, UndoableIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static let title: LocalizedStringResource = "Log a Set of an Exercise"
    static let description = IntentDescription(
        "Logs one completed set of an exercise. Missing load and reps can repeat history; measured duration must be supplied for each timed effort."
    )


    @Parameter(
        title: "Exercise",
        description: "The exercise from the lifter's Marble library to log a set of.",
        requestValueDialog: "Which exercise?"
    )
    var exercise: ExerciseEntity

    @Parameter(
        title: "Reps",
        description: "How many reps were done. Leave empty to copy the reps from the last set of this exercise."
    )
    var reps: Int?

    /// The weight **as a human says it** — for a `singleDumbbellPair` exercise that
    /// is one dumbbell, exactly like the field in `AddSetView`. See `perform()`.
    @Parameter(
        title: "Weight",
        description: "The weight lifted, as the lifter says it. For dumbbell-pair exercises this is the weight of ONE dumbbell, not the total. Leave empty to copy the last set's weight."
    )
    var weight: Double?

    @Parameter(
        title: "Unit",
        description: "Pounds or kilograms. Only set this when the lifter says a unit; otherwise Marble uses the unit this exercise was last logged in."
    )
    var unit: WeightUnitAppEnum?

    @Parameter(title: "Distance", description: "The distance of this effort. Use the distance unit parameter; leave empty to repeat this exercise's last course length.")
    var distance: Double?

    @Parameter(title: "Distance Unit", description: "Meters, kilometers, miles or yards, only when specified.")
    var distanceUnit: DistanceUnitAppEnum?

    @Parameter(title: "Duration in Seconds", description: "The actual measured time for this effort, including decimal seconds such as 7.4. Never copy a previous effort's time.")
    var durationSeconds: Double?

    @Parameter(title: "Performed At", description: "When the set was completed. Leave empty for now.")
    var performedAt: Date?

    @Parameter(title: "Effort", description: "The lifter's reported effort from 1 to 10. Only set when stated.")
    var effort: Int?

    @Parameter(title: "Notes", description: "Notes the lifter asked to attach to this set.")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a set of \(\.$exercise)") {
            \.$reps
            \.$weight
            \.$unit
            \.$distance
            \.$distanceUnit
            \.$durationSeconds
            \.$performedAt
            \.$effort
            \.$notes
        }
    }

    /// `PredictableIntent`: every successful `perform()` teaches the system
    /// *when* this lifter logs *which* exercise, so Siri Suggestions and the
    /// Smart Stack can surface "Log a set of Bench Press" around actual
    /// training times — the personalised signal the widget's
    /// `TimelineEntryRelevance` heuristic cannot supply on its own.
    ///
    /// Only the exercise parameterises the prediction. Reps/weight/unit stay
    /// free on purpose: a predicted invocation then resolves through the same
    /// inherit-from-history path as a spoken request, instead of freezing one
    /// day's numbers into a suggestion.
    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$exercise) { exercise in
            DisplayRepresentation(
                title: "Log a set of \(exercise.name)",
                subtitle: "Reps and weight copied from your last set"
            )
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<LoggedSetEntity> {
        let outcome = try await WorkoutCommands.log(.init(
            exerciseID: exercise.id, exerciseName: exercise.name,
            reps: reps, weight: weight, unit: unit?.weightUnit,
            distance: distance, distanceUnit: distanceUnit?.unit,
            durationSeconds: durationSeconds, performedAt: performedAt,
            effort: effort, notes: notes
        ), undoManager: undoManager)
        guard let entry = outcome.entry else { throw WorkoutIntentFailure(message: outcome.message) }
        return .result(value: LoggedSetEntity(entry), dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

// Compatibility entry point used by existing conversion tests and saved clients.
extension LogSetIntent {
    nonisolated static func convert(_ value: Double, from source: WeightUnit, to target: WeightUnit) -> Double {
        WorkoutCommands.convert(value, from: source, to: target)
    }
}
