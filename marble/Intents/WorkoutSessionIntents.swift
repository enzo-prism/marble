import AppIntents
import Foundation
import SwiftData

// MARK: - Shared session resolution

/// One place that decides which `WorkoutSession` is "the" running one.
///
/// Marble treats *at most one* session as active. Two concurrent active sessions is
/// a known defect class here: `WorkoutView` shows `sessions.first(where: \.isActive)`
/// and `ContentView` routes new sets to the newest active session, so an older
/// second session becomes permanently invisible and un-finishable while still
/// collecting nothing. Every intent below resolves through this helper, and
/// `StartWorkoutIntent` refuses to create a second one at all.
@MainActor
enum WorkoutSessionIntentSupport {
    /// The newest session that has not ended — the same session the Workout tab and
    /// the quick-log sheet resolve to.
    static func activeSession(in context: ModelContext) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Mirrors `WorkoutView.suggestedTitle`: today's split-day title from the active
    /// plan, falling back to a neutral label.
    static func suggestedTitle(in context: ModelContext, now: Date = AppEnvironment.now) -> String {
        let fallback = "Today's Workout"

        var descriptor = FetchDescriptor<SplitPlan>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let plan = (try? context.fetch(descriptor))?.first else { return fallback }
        let calendarWeekday = Calendar.current.component(.weekday, from: now)
        guard let weekday = Weekday.allCases.first(where: { $0.calendarWeekday == calendarWeekday }),
              let day = plan.days.first(where: { $0.weekday == weekday }) else { return fallback }

        let title = day.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }
}

// MARK: - Start

/// Starts a workout session so subsequently logged sets group together.
///
// A genuine workout is represented by ActivityKit and optional HealthKit tracking;
// LongRunningIntent is reserved for computational work, not an idle session.
#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct StartWorkoutIntent: AppIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static let title: LocalizedStringResource = "Start Workout"
    static let description = IntentDescription(
        "Starts a Marble workout so the sets you log are grouped into one session."
    )
    static let openAppWhenRun = true


    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<WorkoutSessionEntity> {
        let context = try AppIntentsSupport.resolvedContainer().mainContext

        // Returning the existing session — rather than inserting a second one — is
        // the whole point of this guard. A duplicate would strand the older session.
        if let existing = WorkoutSessionIntentSupport.activeSession(in: context) {
            return .result(value: WorkoutSessionEntity(existing), dialog: "\(existing.title) is already running. New sets will keep going into it.")
        }

        guard let session = WorkoutCommands.start(in: context) else {
            throw WorkoutIntentFailure(message: "Marble couldn't start the workout.")
        }
        await NativeWorkoutController.shared.start(for: session)

        // A bare session moves none of the weekly numbers (they count
        // `SetEntry` days), but every intent that writes to the store leaves
        // the system surfaces consistent with it — and this restamps the
        // snapshot's `generatedAt` so a workout started by voice can't let it
        // age toward the staleness cliff while the app never foregrounds.
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)

        return .result(value: WorkoutSessionEntity(session), dialog: "Started \(session.title).")
    }
}

// MARK: - Finish

/// Ends the running workout and files it in history.
#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct FinishWorkoutIntent: AppIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static let title: LocalizedStringResource = "Finish Workout"
    static let description = IntentDescription(
        "Ends the workout that's currently running and files it in your workout history."
    )


    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<WorkoutSessionEntity> {
        let context = try AppIntentsSupport.resolvedContainer().mainContext

        guard let session = WorkoutSessionIntentSupport.activeSession(in: context) else {
            throw WorkoutIntentFailure(message: "No workout is running right now.")
        }

        // Capture before saving so the summary can't be affected by the save path.
        let title = session.title
        let setCount = session.entries.count

        guard WorkoutCommands.finish(session, in: context) else {
            throw WorkoutIntentFailure(message: "Marble couldn't finish the workout.")
        }

        await NativeWorkoutController.shared.finish()
        await HealthSessionExporter.shared.exportIfEnabled(from: context)

        // Same cleanup as the Workout tab's Finish button: a rest timer outliving
        // its session leaves a pill counting down over nothing.
        RestActivityController.shared.cancelRest()

        // "Finish my workout" is precisely the moment before the user next
        // glances at the widget — and, run by voice, there is no scene-phase
        // change coming to publish the sets this session collected.
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)

        if setCount > 0 {
            ReviewPrompt.consider(after: .finishedWorkout)
        }

        let setsText = setCount == 1 ? "1 set" : "\(setCount) sets"
        let durationText = DateHelper.formattedDuration(seconds: Int(session.duration.rounded()))
        return .result(value: WorkoutSessionEntity(session), dialog: "Finished \(title) — \(setsText) in \(durationText).")
    }
}
