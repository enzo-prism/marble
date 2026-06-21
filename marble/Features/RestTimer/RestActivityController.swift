import Foundation
import ActivityKit

/// Starts, replaces, and ends the between-sets rest-timer Live Activity.
///
/// Call `startRest(for:)` right after an *interactive* set is logged (quick-log, "Log Again",
/// duplicate). Bulk import deliberately does not call this. Every entry point is a safe no-op
/// when the set has no rest, during UI tests, or when Live Activities are unavailable/disabled
/// (e.g. no widget-extension target yet, or the user turned them off) — so wiring the calls in
/// is harmless even before the widget extension exists.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()
    private init() {}

    private var currentActivity: Activity<RestTimerAttributes>?
    private var endTask: Task<Void, Never>?

    /// Convenience for the logging call sites: pulls the exercise name and rest from a
    /// just-saved `SetEntry`.
    func startRest(for entry: SetEntry) {
        startRest(
            exerciseName: entry.exercise.name,
            restSeconds: entry.restAfterSeconds,
            now: AppEnvironment.now
        )
    }

    /// Starts (or replaces) a rest-timer Live Activity counting down `restSeconds`.
    func startRest(exerciseName: String, restSeconds: Int, now: Date = AppEnvironment.now) {
        guard Self.shouldStart(restSeconds: restSeconds), !TestHooks.isUITesting else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let endsAt = Self.restEndDate(restSeconds: restSeconds, now: now)
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(restEndsAt: endsAt),
            staleDate: endsAt
        )

        endTask?.cancel()
        let previous = currentActivity
        do {
            currentActivity = try Activity.request(
                attributes: RestTimerAttributes(exerciseName: exerciseName),
                content: content,
                pushType: nil
            )
            // Only one rest timer at a time: end the prior one once the new one is live.
            if let previous {
                Task { await previous.end(nil, dismissalPolicy: .immediate) }
            }
            scheduleAutoEnd(at: endsAt)
        } catch {
            // Live Activities can be unavailable (no extension, or user-disabled). Resting is
            // a nicety, so fail silently rather than disrupt logging.
            currentActivity = previous
        }
    }

    /// Ends the current rest timer immediately (e.g. the user logs the next set early).
    func cancelRest() {
        endTask?.cancel()
        let activity = currentActivity
        currentActivity = nil
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func scheduleAutoEnd(at endsAt: Date) {
        let activity = currentActivity
        endTask = Task { [weak self] in
            let delay = max(0, endsAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await activity?.end(nil, dismissalPolicy: .default)
            if self?.currentActivity?.id == activity?.id { self?.currentActivity = nil }
        }
    }

    // MARK: - Pure logic (unit-tested without the ActivityKit runtime)

    /// A rest timer is only meaningful when the set actually prescribes rest.
    nonisolated static func shouldStart(restSeconds: Int) -> Bool { restSeconds > 0 }

    /// The wall-clock moment the rest period ends.
    nonisolated static func restEndDate(restSeconds: Int, now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(restSeconds))
    }
}
