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
// TODO(iOS 27): adopt `LongRunningIntent` here, with the session's progress surfaced
// as a Live Activity for the whole life of the workout, so the system can represent
// a running workout instead of the intent finishing the moment it opens the app.
// The 26.2 SDK ships no `LongRunningIntent`, so 2.3 stays `openAppWhenRun` — do not
// add an `#available` branch for it until the app builds against the 27 SDK.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let description = IntentDescription(
        "Starts a Marble workout so the sets you log are grouped into one session."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppIntentsSupport.resolvedContainer().mainContext

        // Returning the existing session — rather than inserting a second one — is
        // the whole point of this guard. A duplicate would strand the older session.
        if let existing = WorkoutSessionIntentSupport.activeSession(in: context) {
            return .result(dialog: "\(existing.title) is already running. New sets will keep going into it.")
        }

        let now = AppEnvironment.now
        let session = WorkoutSession(
            title: WorkoutSessionIntentSupport.suggestedTitle(in: context, now: now),
            startedAt: now,
            createdAt: now,
            updatedAt: now
        )
        context.insert(session)

        guard context.saveOrRollback() else {
            return .result(dialog: "Marble couldn't start the workout.")
        }

        return .result(dialog: "Started \(session.title).")
    }
}

// MARK: - Finish

/// Ends the running workout and files it in history.
struct FinishWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Workout"
    static let description = IntentDescription(
        "Ends the workout that's currently running and files it in your workout history."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppIntentsSupport.resolvedContainer().mainContext

        guard let session = WorkoutSessionIntentSupport.activeSession(in: context) else {
            return .result(dialog: "No workout is running right now.")
        }

        let now = AppEnvironment.now
        // Capture before saving so the summary can't be affected by the save path.
        let title = session.title
        let setCount = session.entries.count

        session.finish(at: now)
        guard context.saveOrRollback() else {
            return .result(dialog: "Marble couldn't finish the workout.")
        }

        // Same cleanup as the Workout tab's Finish button: a rest timer outliving
        // its session leaves a pill counting down over nothing.
        RestActivityController.shared.cancelRest()

        let setsText = setCount == 1 ? "1 set" : "\(setCount) sets"
        let durationText = DateHelper.formattedDuration(seconds: Int(session.duration.rounded()))
        return .result(dialog: "Finished \(title) — \(setsText) in \(durationText).")
    }
}
