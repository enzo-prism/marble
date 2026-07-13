import AppIntents
import Foundation
import SwiftData
import SwiftUI

/// Shares the app's model container with intents that may run while the app
/// is launched in the background by the system.
@MainActor
enum AppIntentsSupport {
    static var container: ModelContainer?

    static func resolvedContainer() -> ModelContainer {
        if let container {
            return container
        }
        let created = PersistenceController.makeContainer(useInMemory: TestHooks.useInMemoryStore)
        container = created
        return created
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

struct LogLastSetAgainIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Last Set Again"
    static let description = IntentDescription("Logs another set of your most recent exercise with the same metrics.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppIntentsSupport.resolvedContainer().mainContext
        var descriptor = FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let latest = (try? context.fetch(descriptor))?.first else {
            return .result(dialog: "No sets logged yet. Open Marble to log your first set.")
        }

        let duplicate = latest.duplicated(at: AppEnvironment.now)
        context.insert(duplicate)
        let latestID = latest.id
        let goalDescriptor = FetchDescriptor<SprintGoalSnapshot>(
            predicate: #Predicate { $0.setEntryID == latestID }
        )
        if let goal = (try? context.fetch(goalDescriptor))?.first {
            context.insert(SprintGoalSnapshot(
                setEntryID: duplicate.id,
                exerciseID: duplicate.exercise.id,
                distance: goal.distance,
                distanceUnit: goal.distanceUnit,
                repetitionNumber: nil,
                repetitionCount: goal.repetitionCount,
                targetLowerSeconds: goal.targetLowerSeconds,
                targetUpperSeconds: goal.targetUpperSeconds,
                isInferred: goal.isInferred,
                createdAt: duplicate.createdAt
            ))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            return .result(dialog: "Couldn't log the set. Open Marble to try again.")
        }

        return .result(dialog: "Logged another set of \(latest.exercise.name).")
    }
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
    }
}
