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
    func perform() async throws -> some IntentResult & ReturnsValue<LoggedSetEntity> & ProvidesDialog {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let id = set.id
        guard let entry = try context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == id })).first,
              entry.importedWorkout == nil else {
            throw WorkoutIntentFailure(message: "That manual set is no longer available. Open Marble to choose a set.")
        }
        let request = WorkoutCommands.LogRequest(exerciseID: entry.exercise.id, exerciseName: entry.exercise.name,
            reps: reps, weight: weight, unit: unit?.weightUnit, distance: distance, distanceUnit: distanceUnit?.unit,
            durationSeconds: durationSeconds, effort: effort, notes: notes)
        guard request.isValid else { throw WorkoutIntentFailure(message: "Check the corrected values and try again.") }
        let metrics = entry.exercise.metrics
        guard (reps == nil || metrics.usesReps), (weight == nil && unit == nil || metrics.usesWeight),
              (distance == nil && distanceUnit == nil || metrics.usesDistance),
              (durationSeconds == nil || metrics.usesDuration) else {
            throw WorkoutIntentFailure(message: "This exercise doesn't use one of those metrics. Open Marble to check the exercise settings.")
        }
        if weight != nil || unit != nil {
            let targetUnit = unit?.weightUnit ?? entry.weightUnit
            let inherited = entry.exercise.displayedWeightInput(from: entry.weight).map {
                WorkoutCommands.convert($0, from: entry.weightUnit, to: targetUnit)
            }
            entry.weight = entry.exercise.storedWeight(from: weight ?? inherited)
            entry.weightUnit = targetUnit
        }
        if let reps { entry.reps = reps }
        if let distanceUnit {
            if distance == nil, let previous = entry.distance {
                entry.distance = entry.distanceUnit.meters(from: previous) / distanceUnit.unit.metersPerUnit
            }
            entry.distanceUnit = distanceUnit.unit
        }
        if let distance { entry.distance = distance }
        if let durationSeconds {
            let tenths = SprintTiming.tenths(fromSeconds: durationSeconds)
            entry.durationSeconds = max(1, SprintTiming.wholeSeconds(fromTenths: tenths))
            if let detail = try context.fetch(FetchDescriptor<SprintRepDetail>(predicate: #Predicate { $0.setEntryID == id })).first {
                detail.durationTenths = tenths
            } else {
                context.insert(SprintRepDetail(setEntryID: id, durationTenths: tenths, targetLowerTenths: 0, targetUpperTenths: 0))
            }
        }
        if let effort { entry.difficulty = effort }
        if let notes { entry.notes = notes.isEmpty ? nil : notes }
        entry.updatedAt = AppEnvironment.now
        guard context.saveOrRollback() else { throw WorkoutIntentFailure(message: "Marble couldn't save that correction.") }
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [entry.exercise.id])
        let result = LoggedSetEntity(entry)
        return .result(value: result, dialog: "Updated. \(result.summary)")
    }
}
