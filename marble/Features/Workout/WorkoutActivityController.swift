import ActivityKit
import Foundation
import SwiftData

@MainActor
enum WorkoutActivityController {
    private static var operation: Task<Void, Never>?
    private static var generation = 0

    static var hasRunningWorkout: Bool {
        guard let context = AppIntentsSupport.container?.mainContext else { return false }
        return WorkoutSessionIntentSupport.activeSession(in: context) != nil
    }

    static func recoverRest() async {
        guard RestActivityController.shared.activeRest == nil,
              let context = AppIntentsSupport.container?.mainContext,
              let session = WorkoutSessionIntentSupport.activeSession(in: context),
              let state = await savedState(sessionID: session.id),
              let endsAt = state.restEndsAt, endsAt > AppEnvironment.now else { return }
        RestActivityController.shared.startRest(exerciseName: state.exerciseName ?? session.title,
            restSeconds: Int(ceil(endsAt.timeIntervalSince(AppEnvironment.now))))
    }

    private nonisolated static func savedState(sessionID: UUID) async -> WorkoutActivityAttributes.ContentState? {
        Activity<WorkoutActivityAttributes>.activities.first {
            $0.attributes.sessionID == sessionID && ($0.activityState == .active || $0.activityState == .stale)
        }?.content.state
    }

    static func refresh() async {
        WatchWorkoutCoordinator.shared.publish()
        guard !TestHooks.isUITesting,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let context = AppIntentsSupport.container?.mainContext else { return }
        let session = WorkoutSessionIntentSupport.activeSession(in: context)
        let identity = session.map { WorkoutActivityAttributes(sessionID: $0.id, startedAt: $0.startedAt) }
        let state = session.map { session in
            WorkoutActivityAttributes.ContentState(
                title: session.title, exerciseName: session.orderedEntries.last?.exercise.name,
                setCount: session.entries.count,
                restEndsAt: RestActivityController.shared.activeRest?.endsAt,
                updatedAt: AppEnvironment.now
            )
        }
        generation += 1
        let expected = generation
        let previous = operation
        let next = Task {
            await previous?.value
            guard expected == generation else { return }
            await updateSystemActivity(identity: identity, state: state)
        }
        operation = next
        await next.value
    }

    private nonisolated static func updateSystemActivity(identity: WorkoutActivityAttributes?, state: WorkoutActivityAttributes.ContentState?) async {
        let activities = Activity<WorkoutActivityAttributes>.activities
        guard let identity, let state else {
            for activity in activities { await activity.end(activity.content, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(8 * 3600))
        let matching = activities.first { $0.attributes.sessionID == identity.sessionID && ($0.activityState == .active || $0.activityState == .stale) }
        for activity in activities where activity.id != matching?.id {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        if let matching {
            await matching.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Failure leaves the local workout usable (for example, activities disabled).
            _ = try? Activity.request(attributes: identity, content: content, pushType: nil)
        }
    }
}
