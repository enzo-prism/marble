import AppIntents
import Foundation
import SwiftData

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct StartRestIntent: LiveActivityIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static let title: LocalizedStringResource = "Start Rest"
    static let description = IntentDescription("Starts a rest timer for the current exercise without logging a set.")
    @Parameter(title: "Seconds", description: "The requested rest duration in seconds, from 1 to 3600.", default: 90)
    var seconds: Int
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...3600).contains(seconds) else { return .result(dialog: "Choose a rest between 1 second and 1 hour.") }
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        let exercise = try WorkoutCommands.latestRepeatSource(in: context)?.exercise.name ?? "Workout"
        RestActivityController.shared.startRest(exerciseName: exercise, restSeconds: seconds)
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        await WorkoutActivityController.refresh()
        return .result(dialog: "Rest started for \(seconds) seconds.")
    }
}

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct AdjustRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Rest Time"
    static let description = IntentDescription("Adds the specified number of seconds to the current rest timer.")
    @Parameter(title: "Seconds", description: "Extra rest in seconds. For a minute, pass 60.", default: 30)
    var seconds: Int
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...3600).contains(seconds) else { return .result(dialog: "Choose between 1 and 3600 extra seconds.") }
        await WorkoutActivityController.recoverRest()
        guard RestActivityController.shared.activeRest != nil else { return .result(dialog: "No rest timer is running.") }
        RestActivityController.shared.extend(by: Double(seconds))
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        await WorkoutActivityController.refresh()
        return .result(dialog: "Added \(seconds) seconds of rest.")
    }
}

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let description = IntentDescription("Ends the current rest timer without ending the workout.")
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        RestActivityController.shared.cancelRest()
        await RestActivityController.shared.waitForPendingLiveActivityOperation()
        await WorkoutActivityController.refresh()
        return .result(dialog: "Rest ended.")
    }
}
