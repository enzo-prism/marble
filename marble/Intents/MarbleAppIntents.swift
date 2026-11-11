import AppIntents
import Foundation
import SwiftData
import SwiftUI

/// Shares the app's model container with intents that may run while the app
/// is launched in the background by the system.
@MainActor
enum AppIntentsSupport {
    static var container: ModelContainer?
    static var storageFailure: PersistenceOpenFailure?

    /// Publishes the app's container to this type's own accessor **and** to
    /// `AppDependencyManager`, Apple's documented dependency mechanism for
    /// intents. Call it exactly where the container is created —
    /// `MarbleApp.init`, the first thing that runs in the process, including when
    /// Siri launches the app in the background to perform an intent.
    ///
    /// ⚠️ **The intents deliberately still read `resolvedContainer()` rather
    /// than an `@Dependency` property.** Adopting the wrapper (tried
    /// 2026-07-25) traps at runtime — *"AppDependency of type ModelContainer.Type
    /// was not initialized prior to access. Dependency values can only be
    /// accessed inside of the intent perform flow"* — because `LogSetIntentTests`
    /// and `AppIntentEntityTests` call `perform()` directly instead of going
    /// through the system's flow. Registration is kept so the documented
    /// mechanism is populated for anything the system does drive; do not swap the
    /// call sites over without first solving the direct-`perform()` test path.
    ///
    /// Registration is idempotent, so tests can call it per case.
    static func register(container: ModelContainer) {
        storageFailure = nil
        self.container = container
        AppDependencyManager.shared.add(dependency: container)
    }

    static func resolvedContainer() throws -> ModelContainer {
        if let storageFailure { throw storageFailure }
        if let container {
            return container
        }
        let created = try PersistenceController.openContainer(useInMemory: TestHooks.useInMemoryStore)
        register(container: created)
        return created
    }

    /// Refreshes the system surfaces that mirror the store — the Weekly Goal
    /// widget snapshot and the weekly-goal reminder — after an intent has
    /// saved a change.
    ///
    /// Intents run without a scene: Siri launches the app in the background,
    /// so `ContentView`'s scene-phase handler (the only other caller of this
    /// pair) never fires. Skipping this was the shipped defect where a
    /// voice-logged third session left the widget reading "2 of 3" and still
    /// fired the at-risk nudge. Apple's widget guidance is explicit that any
    /// code a timeline update needs must run *before* `perform()` returns,
    /// which is why call sites `await` this instead of spinning off a `Task`
    /// the process could be suspended under.
    ///
    /// The Control Center `QuickLogControl` needs no reload here: it is a
    /// `StaticControlConfiguration` button with no value provider, so it has
    /// no state to go stale.
    static func refreshSystemSurfaces(modelContext: ModelContext, changedExerciseIDs: [UUID] = []) async {
        // Same pair, same store as the scene-phase handler in `ContentView` —
        // the publisher's own doc comment asks to be called wherever
        // `WeeklyGoalReminder.sync` is, because both answer "how does this
        // week stand?" and must never disagree.
        await WorkoutActivityController.refresh()
        await WorkoutSessionSpotlightIndex.refresh()
        WeeklyGoalWidgetPublisher.publish(modelContext: modelContext)
        await WeeklyGoalReminder.sync(modelContext: modelContext)
        // The indexed exercises carry personal bests and recency that a
        // voice-logged set just changed; awaited for the same reason as above.
        if !changedExerciseIDs.isEmpty { await ExerciseSpotlightIndex.refreshAfterSetChange(identifiers: changedExerciseIDs) }
    }
}

extension Notification.Name {
    static let marbleOpenQuickLog = Notification.Name("marbleOpenQuickLog")
}

struct OpenQuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Set"
    static let description = IntentDescription("Opens Marble straight to the set logger.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .marbleOpenQuickLog, object: nil)
        return .result()
    }
}

#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct LogLastSetAgainIntent: LiveActivityIntent, UndoableIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static let title: LocalizedStringResource = "Log Last Set Again"
    static let description = IntentDescription("Logs another set of your most recent exercise with the same metrics.")


    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<LoggedSetEntity> {
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        guard let latest = try WorkoutCommands.latestRepeatSource(in: context) else {
            throw WorkoutIntentFailure(message: "No sets in the current workout yet. Log a set first.")
        }
        guard let duplicate = WorkoutCommands.repeatSet(
            latest, into: WorkoutSessionIntentSupport.activeSession(in: context), in: context
        ) else {
            throw WorkoutIntentFailure(message: "Couldn't log the set. Open Marble to try again.")
        }
        let duplicateID = duplicate.id
        let goalDescriptor = FetchDescriptor<SprintGoalSnapshot>(predicate: #Predicate { $0.setEntryID == duplicateID })
        let duplicatedGoalID = try context.fetch(goalDescriptor).first?.id
        await RestActivityController.shared.waitForPendingLiveActivityOperation()

        // This set may have just completed the week — the widget and the
        // at-risk nudge must hear about it before the intent returns.
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context, changedExerciseIDs: [latest.exercise.id])

        IntentUndo.registerLoggedSet(
            entryID: duplicate.id,
            goalSnapshotID: duplicatedGoalID,
            container: try AppIntentsSupport.resolvedContainer(),
            undoManager: undoManager,
            actionName: "Log Last Set Again"
        )

        let confirmed = LoggedSetEntity(duplicate)
        return .result(value: confirmed, dialog: IntentDialog(stringLiteral: confirmed.summary))
    }
}

#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct ReviewWorkoutTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Workout Text"
    static let description = IntentDescription("Opens Marble to review a pasted workout before adding it to the journal.")
    static let openAppWhenRun = true
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(
        title: "Workout text",
        description: "The workout as the lifter wrote or said it, in plain language or gym notation (e.g. \"bench 3x8 at 185, then pull-ups 3x10\"). It can cover several exercises or days. Nothing is logged until the lifter reviews it in Marble."
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingTextImport.stage(text)
        NotificationCenter.default.post(name: .marbleOpenTextImport, object: nil)
        return .result()
    }
}

#if SIRI_AI_PREVIEW
// Siri AI Developer Preview: exposes this intent to Siri as a tool it can call
// from natural requests. Needs the Xcode 27.3 beta SDK — see SiriAIPreview/README.md.
@AppIntent(.tool)
#endif
struct ReviewWorkoutFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Workout File"
    static let description = IntentDescription("Opens Marble to review a Hevy, Strong, or Notes workout file before adding it to the journal.")
    static let openAppWhenRun = true
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(
        title: "Workout file",
        description: "A Hevy or Strong CSV export, or a text file of workout notes. Nothing is logged until the lifter reviews it in Marble."
    )
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingTextImport.stage(intentFileText(file) ?? "")
        NotificationCenter.default.post(name: .marbleOpenTextImport, object: nil)
        return .result()
    }
}

private func intentFileText(_ file: IntentFile) -> String? {
    let data: Data
    if !file.data.isEmpty {
        data = file.data
    } else if let url = file.fileURL, let loaded = try? Data(contentsOf: url) {
        data = loaded
    } else {
        return nil
    }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
}

struct MarbleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickLogIntent(),
            phrases: [
                "Log a set in \(.applicationName)",
                "Start logging in \(.applicationName)"
            ],
            shortTitle: "Log a Set",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: LogLastSetAgainIntent(),
            phrases: [
                "Log my last set again in \(.applicationName)",
                "Repeat my last set in \(.applicationName)"
            ],
            shortTitle: "Log Last Set Again",
            systemImageName: "arrow.clockwise.circle"
        )
        // Parameterised phrase: the exercise is resolved through `ExerciseQuery`,
        // whose `suggestedEntities()` is what Siri offers when the name is unclear.
        AppShortcut(
            intent: LogSetIntent(),
            phrases: [
                "Log a set of \(\.$exercise) in \(.applicationName)",
                "Add a \(\.$exercise) set to \(.applicationName)",
                "Log an exercise set in \(.applicationName)"
            ],
            shortTitle: "Log a Set of an Exercise",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a workout in \(.applicationName)",
                "Start my \(.applicationName) workout"
            ],
            shortTitle: "Start Workout",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: FinishWorkoutIntent(),
            phrases: [
                "Finish my workout in \(.applicationName)",
                "End my \(.applicationName) workout"
            ],
            shortTitle: "Finish Workout",
            systemImageName: "flag.checkered"
        )
        AppShortcut(
            intent: ReviewWorkoutTextIntent(),
            phrases: [
                "Import a workout in \(.applicationName)",
                "Review a workout in \(.applicationName)"
            ],
            shortTitle: "Import a Workout",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: StartRestIntent(),
            phrases: ["Start rest in \(.applicationName)"],
            shortTitle: "Start Rest",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: SkipRestIntent(),
            phrases: ["Skip rest in \(.applicationName)"],
            shortTitle: "Skip Rest",
            systemImageName: "forward.end"
        )
        AppShortcut(
            intent: FindWorkoutsIntent(),
            phrases: ["Find my workouts in \(.applicationName)"],
            shortTitle: "Find Workouts",
            systemImageName: "magnifyingglass"
        )
    }
}
