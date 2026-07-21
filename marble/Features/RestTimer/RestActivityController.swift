import Foundation
import Observation
import ActivityKit

/// The rest period currently counting down, mirrored by every in-app surface
/// (the tab-bar accessory pill) alongside the system Live Activity.
nonisolated struct ActiveRest: Equatable {
    let exerciseName: String
    let endsAt: Date
}

/// Starts, replaces, and ends the between-sets rest timer.
///
/// Call `startRest(for:)` right after an *interactive* set is logged (quick-log, "Log Again",
/// duplicate). Bulk import deliberately does not call this. Two surfaces hang off one state
/// machine: the observable `activeRest` drives the in-app tab-bar pill, and a Live Activity
/// mirrors the countdown on the Lock Screen / Dynamic Island. The Live Activity is a safe
/// no-op when unavailable/disabled (e.g. user turned them off) — the in-app pill still works.
@MainActor
@Observable
final class RestActivityController {
    static let shared = RestActivityController()

    /// The rest period currently counting down, or `nil` when idle. Drives the
    /// in-app rest pill; cleared on cancel, replacement, and scheduled expiry.
    private(set) var activeRest: ActiveRest?

    @ObservationIgnored private var currentActivity: Activity<RestTimerAttributes>?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    /// Convenience for the logging call sites: pulls the exercise name and rest from a
    /// just-saved `SetEntry`.
    func startRest(for entry: SetEntry) {
        startRest(
            exerciseName: entry.exercise.name,
            restSeconds: entry.restAfterSeconds,
            now: AppEnvironment.now
        )
    }

    /// Starts (or replaces) a rest timer counting down `restSeconds`.
    func startRest(exerciseName: String, restSeconds: Int) {
        startRest(exerciseName: exerciseName, restSeconds: restSeconds, now: AppEnvironment.now)
    }

    func startRest(exerciseName: String, restSeconds: Int, now: Date) {
        guard Self.shouldStart(restSeconds: restSeconds), Self.isRestSurfaceEnabled else { return }
        let endsAt = Self.restEndDate(restSeconds: restSeconds, now: now)
        beginRestSession(exerciseName: exerciseName, endsAt: endsAt)
        startLiveActivity(exerciseName: exerciseName, endsAt: endsAt)
    }

    /// Sets the in-app rest state (the tab-bar pill) and schedules its auto-clear.
    /// Separate from the Live Activity so unit tests can drive the state machine
    /// without touching the ActivityKit runtime.
    func beginRestSession(exerciseName: String, endsAt: Date) {
        endTask?.cancel()
        activeRest = ActiveRest(exerciseName: exerciseName, endsAt: endsAt)
        scheduleAutoEnd(at: endsAt)
    }

    /// Adds `seconds` to the rest already counting down (the Live Activity's "+30s" button).
    ///
    /// A no-op when nothing is resting — the button can outlive the timer on a stale
    /// Lock Screen render, and extending a rest that already ended would be surprising.
    func extend(by seconds: TimeInterval) {
        extend(by: seconds, now: AppEnvironment.now)
    }

    func extend(by seconds: TimeInterval, now: Date) {
        guard let activeRest else { return }
        // Extend from the *current* end, not from now, so repeated taps accumulate
        // (+30 then +30 = a full extra minute, not 30 seconds from the second tap).
        let endsAt = Self.extendedEnd(from: activeRest.endsAt, by: seconds, now: now)
        beginRestSession(exerciseName: activeRest.exerciseName, endsAt: endsAt)
        updateLiveActivity(endsAt: endsAt)
    }

    /// Ends the current rest timer immediately (e.g. the user logs the next set
    /// early, or taps End on the in-app pill).
    func cancelRest() {
        endTask?.cancel()
        activeRest = nil
        let activity = currentActivity
        currentActivity = nil
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Clears a rest that expired while the auto-end task couldn't run (the app
    /// was suspended mid-rest). Called when the scene becomes active again.
    func pruneExpiredRest(now suppliedNow: Date? = nil) {
        let now = suppliedNow ?? AppEnvironment.now
        guard let activeRest, activeRest.endsAt <= now else { return }
        endTask?.cancel()
        self.activeRest = nil
        let activity = currentActivity
        currentActivity = nil
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .default) }
        }
    }

    private func startLiveActivity(exerciseName: String, endsAt: Date) {
        guard !TestHooks.isUITesting else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(restEndsAt: endsAt),
            staleDate: endsAt
        )

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
        } catch {
            // Live Activities can be unavailable (no extension, or user-disabled). Resting is
            // a nicety, so fail silently rather than disrupt logging.
            currentActivity = previous
        }
    }

    /// Pushes a new end date into the running activity so the Lock Screen / Dynamic Island
    /// countdown re-targets. Safe when no activity is live (Live Activities disabled, UI test).
    private func updateLiveActivity(endsAt: Date) {
        guard let activity = currentActivity else { return }
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(restEndsAt: endsAt),
            staleDate: endsAt
        )
        Task { await activity.update(content) }
    }

    private func scheduleAutoEnd(at endsAt: Date) {
        endTask = Task { [weak self] in
            let delay = max(0, endsAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            self?.completeRest(endingAt: endsAt)
        }
    }

    private func completeRest(endingAt endsAt: Date) {
        if activeRest?.endsAt == endsAt {
            activeRest = nil
        }
        let activity = currentActivity
        currentActivity = nil
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .default) }
        }
    }

    // MARK: - Pure logic (unit-tested without the ActivityKit runtime)

    /// A rest timer is only meaningful when the set actually prescribes rest.
    nonisolated static func shouldStart(restSeconds: Int) -> Bool { restSeconds > 0 }

    /// The wall-clock moment the rest period ends.
    nonisolated static func restEndDate(restSeconds: Int, now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(restSeconds))
    }

    /// The end date after adding `seconds` to a rest that ends at `currentEnd`.
    ///
    /// Extending from `currentEnd` (not from `now`) is what makes repeated "+30s" taps
    /// accumulate. The `max` clamp covers the stale-render case: if the rest already elapsed,
    /// the extension starts from `now` so the result is never in the past — otherwise a tap on
    /// a lagging Lock Screen would produce an already-expired timer that vanishes instantly.
    nonisolated static func extendedEnd(from currentEnd: Date, by seconds: TimeInterval, now: Date) -> Date {
        max(currentEnd, now).addingTimeInterval(seconds)
    }

    /// Rest surfaces stay out of UI-test runs (they'd overlay unrelated flows)
    /// unless a test opts in via `MARBLE_ENABLE_REST_PILL`.
    private static var isRestSurfaceEnabled: Bool {
        !TestHooks.isUITesting || TestHooks.enableRestPillInUITests
    }
}
