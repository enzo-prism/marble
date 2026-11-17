import AppIntents
import SwiftData

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct CorrectLoggedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Correct Logged Set"
    static let description = IntentDescription("Corrects the specific confirmed set supplied as input. Never selects an unrelated latest set. Unspecified values stay unchanged.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Set", description: "The confirmed set to correct, such as the result of Log a Set.") var set: LoggedSetEntity
    @Parameter(title: "Reps") var reps: Int?
    @Parameter(title: "Weight", description: "For a dumbbell pair, the weight of one dumbbell.") var weight: Double?
    @Parameter(title: "Weight Unit") var unit: WeightUnitAppEnum?
    @Parameter(title: "Distance") var distance: Double?
    @Parameter(title: "Distance Unit") var distanceUnit: DistanceUnitAppEnum?
    @Parameter(title: "Duration in Seconds", description: "The corrected measured duration, including tenths.") var durationSeconds: Double?
    @Parameter(title: "Effort") var effort: Int?
    @Parameter(title: "Notes") var notes: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LoggedSetEntity> & ProvidesDialog & ShowsSnippetIntent {
        let entry = try await WorkoutCommands.correct(entryID: set.id, .init(
            reps: reps, weight: weight, unit: unit?.weightUnit, distance: distance, distanceUnit: distanceUnit?.unit,
            durationSeconds: durationSeconds, effort: effort, notes: notes))
        let result = LoggedSetEntity(entry)
        return .result(value: result, dialog: "Updated. \(result.summary)",
                       snippetIntent: LoggedSetSnippetIntent(setID: entry.id, createdSet: false))
    }
}
