import Foundation
import Observation
import ActivityKit
import UserNotifications

/// The rest period currently counting down, mirrored by every in-app surface
/// (the tab-bar accessory pill) alongside the system Live Activity.
nonisolated struct ActiveRest: Equatable {
    let exerciseName: String
    let endsAt: Date
}

/// Process-independent description of a Marble rest Live Activity. ActivityKit owns the
/// actual activities and can keep them alive after Marble's process exits, so this value is
/// the boundary between the controller's state machine and the system inventory.
nonisolated struct RestLiveActivitySnapshot: Equatable {
    let id: String
    let exerciseName: String
    let endsAt: Date
    let startedAt: Date?
    let isOngoing: Bool

    init(
        id: String,
        exerciseName: String,
        endsAt: Date,
        startedAt: Date? = nil,
        isOngoing: Bool
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.endsAt = endsAt
        self.startedAt = startedAt
        self.isOngoing = isOngoing
    }
}

nonisolated struct RestLiveActivityReconciliation: Equatable {
    let keeper: RestLiveActivitySnapshot?
    let activityIDsToEnd: [String]
}

/// Small ActivityKit seam: production enumerates the system-owned activities; unit tests use
/// an in-memory implementation to prove ordering and the single-activity invariant.
@MainActor
protocol RestLiveActivityClient: AnyObject {
    var activitiesEnabled: Bool { get }
    func snapshots() -> [RestLiveActivitySnapshot]
    func request(exerciseName: String, endsAt: Date, staleDate: Date, startedAt: Date) throws -> String
    func update(activityID: String, endsAt: Date, staleDate: Date) async
    func endImmediately(activityID: String) async
}

@MainActor
private final class ActivityKitRestLiveActivityClient: RestLiveActivityClient {
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func snapshots() -> [RestLiveActivitySnapshot] {
        Activity<RestTimerAttributes>.activities.map { activity in
            RestLiveActivitySnapshot(
                id: activity.id,
                exerciseName: activity.attributes.exerciseName,
                endsAt: activity.content.state.restEndsAt,
                startedAt: activity.attributes.startedAt,
                isOngoing: activity.activityState == .active || activity.activityState == .stale
            )
        }
    }

    func request(exerciseName: String, endsAt: Date, staleDate: Date, startedAt: Date) throws -> String {
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(restEndsAt: endsAt),
            staleDate: staleDate
        )
        return try Activity.request(
            attributes: RestTimerAttributes(exerciseName: exerciseName, startedAt: startedAt),
            content: content,
            pushType: nil
        ).id
    }

    func update(activityID: String, endsAt: Date, staleDate: Date) async {
        guard let activity = Activity<RestTimerAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(restEndsAt: endsAt),
            staleDate: staleDate
        )
        await activity.update(content)
    }

    func endImmediately(activityID: String) async {
        guard let activity = Activity<RestTimerAttributes>.activities.first(where: { $0.id == activityID }) else {
            return
        }
        // A finished rest has no useful final score or summary. Passing the current content
        // satisfies ActivityKit's final-content guidance while `.immediate` prevents 0:00
        // cards from accumulating for up to four hours on the Lock Screen.
        await activity.end(activity.content, dismissalPolicy: .immediate)
    }
}

/// Seam for the single "rest complete" local notification that fires when the countdown
/// reaches zero while Marble is backgrounded or the phone is locked. In-process the
/// auto-end task handles completion, but that task is suspended with the app — a scheduled
/// notification is the only alert the system will deliver on Marble's behalf.
///
/// Deliberately a notification and *not* an ActivityKit `AlertConfiguration`: the HIG says
/// never to pair both for the same moment, and only the notification covers the
/// suspended-app case that actually matters between sets. Unit tests inject a fake; the
/// default test seam is inert so the suite never touches the real notification center.
@MainActor
protocol RestEndAlertClient: AnyObject {
    func scheduleAlert(exerciseName: String, endsAt: Date)
    func cancelAlert()
}

@MainActor
private final class UserNotificationRestEndAlertClient: RestEndAlertClient {
    /// One fixed identifier: at most one rest-end alert is ever pending, and re-scheduling
    /// replaces it wholesale — the same anti-spam shape as `WeeklyGoalReminder`.
    static let requestIdentifier = "marble.restTimer.restComplete"

    func scheduleAlert(exerciseName: String, endsAt: Date) {
        // Rest surfaces are opt-in under UI testing, and even then a real banner firing
        // mid-flow would perturb unrelated assertions.
        guard !TestHooks.isUITesting else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            // Never prompt from a rest start — the alert rides on whatever authorization the
            // user already granted for their own reminders and stays silent otherwise
            // (`WeeklyGoalReminder` precedent).
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "\(exerciseName) — time for your next set."
            content.sound = .default
            // Default interruption level on purpose: the time-sensitive entitlement is not in
            // `marble.entitlements`, and `.timeSensitive` without it is silently downgraded
            // anyway. When the app is foreground at zero there is no delegate opting into
            // banner presentation, so iOS suppresses this notification — the disappearing
            // in-app pill is the foreground signal, and the user is never double-alerted.

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: endsAt
            )
            // A one-shot calendar trigger pinned to the rest's wall-clock end. If `endsAt`
            // is already past by delivery time the trigger simply never fires.
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: trigger)
            )
        }
    }

    func cancelAlert() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }
}

/// Default for the test seam: most controller tests exercise timing/invariants and must not
/// schedule real notifications from the test host. Alert-specific tests inject a recording fake.
@MainActor
final class InertRestEndAlertClient: RestEndAlertClient {
    func scheduleAlert(exerciseName: String, endsAt: Date) {}
    func cancelAlert() {}
}

/// Starts, replaces, and ends the between-sets rest timer.
///
/// Call `startRest(for:)` right after an *interactive* set is logged (quick-log, "Log Again",
/// duplicate). Bulk import deliberately does not call this. Three surfaces hang off one state
/// machine: the observable `activeRest` drives the in-app tab-bar pill, a Live Activity
/// mirrors the countdown on the Lock Screen / Dynamic Island, and a single pending local
/// notification alerts a backgrounded user at completion. The Live Activity and the alert
/// are each a safe no-op when unavailable/denied — the in-app pill still works.
@MainActor
@Observable
final class RestActivityController {
    static let shared = RestActivityController()

    /// The rest period currently counting down, or `nil` when idle. Drives the
    /// in-app rest pill; cleared on cancel, replacement, and scheduled expiry.
    private(set) var activeRest: ActiveRest?

    @ObservationIgnored private let liveActivities: any RestLiveActivityClient
    @ObservationIgnored private let restEndAlerts: any RestEndAlertClient
    @ObservationIgnored private var currentActivityID: String?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var liveActivityTask: Task<Void, Never>?
    @ObservationIgnored private var liveActivityGeneration = 0

    init() {
        self.liveActivities = ActivityKitRestLiveActivityClient()
        self.restEndAlerts = UserNotificationRestEndAlertClient()
    }

    init(
        liveActivities: any RestLiveActivityClient,
        restEndAlerts: any RestEndAlertClient = InertRestEndAlertClient()
    ) {
        self.liveActivities = liveActivities
        self.restEndAlerts = restEndAlerts
    }

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
        // Scheduled outside the Live Activity path on purpose: the backgrounded-completion
        // alert must still fire when Live Activities are disabled and only the pill runs.
        restEndAlerts.scheduleAlert(exerciseName: exerciseName, endsAt: endsAt)
        replaceLiveActivity(startedAt: now)
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
    func extend(by seconds: TimeInterval, activityID: String? = nil) {
        extend(by: seconds, now: AppEnvironment.now, activityID: activityID)
    }

    func extend(by seconds: TimeInterval, now: Date, activityID: String? = nil) {
        if let activityID {
            let plan = Self.reconciliationPlan(
                for: liveActivities.snapshots(),
                now: now,
                preferredActivityID: currentActivityID
            )
            guard plan.keeper?.id == activityID, let keeper = plan.keeper else {
                // A button on an expired/duplicate card must never mutate the newer timer.
                reconcileLiveActivities(now: now)
                return
            }
            adopt(keeper, preservingNewerLocalDeadline: true)
        } else if activeRest == nil, let keeper = Self.reconciliationPlan(
            for: liveActivities.snapshots(),
            now: now
        ).keeper {
            // LiveActivityIntent may launch a fresh app process. Rehydrate the controller
            // from ActivityKit so +30s still works without the old in-memory pointer.
            adopt(keeper)
        }

        guard let activeRest else { return }
        // Extend from the *current* end, not from now, so repeated taps accumulate
        // (+30 then +30 = a full extra minute, not 30 seconds from the second tap).
        let endsAt = Self.extendedEnd(from: activeRest.endsAt, by: seconds, now: now)
        beginRestSession(exerciseName: activeRest.exerciseName, endsAt: endsAt)
        // The pending completion alert tracks the extended deadline, otherwise it would fire
        // mid-rest at the original end. Re-adding the fixed identifier replaces it wholesale.
        restEndAlerts.scheduleAlert(exerciseName: activeRest.exerciseName, endsAt: endsAt)
        updateLiveActivity(endsAt: endsAt)
    }

    /// Ends the current rest timer immediately (e.g. the user logs the next set
    /// early, or taps End on the in-app pill).
    func cancelRest(activityID: String? = nil) {
        if let activityID {
            let plan = Self.reconciliationPlan(
                for: liveActivities.snapshots(),
                now: AppEnvironment.now,
                preferredActivityID: currentActivityID
            )
            if let keeper = plan.keeper, keeper.id != activityID {
                // The user acted on an old duplicate card. Remove every duplicate while
                // preserving the one current timer instead of canceling the wrong rest.
                adopt(keeper, preservingNewerLocalDeadline: true)
                endLiveActivities(plan.activityIDsToEnd)
                return
            }
        }

        endTask?.cancel()
        activeRest = nil
        currentActivityID = nil
        // The user ended rest early — the completion alert must not fire later for a
        // rest that no longer exists.
        restEndAlerts.cancelAlert()
        endLiveActivities(liveActivities.snapshots().map(\.id))
    }

    /// Clears a rest that expired while the auto-end task couldn't run (the app
    /// was suspended mid-rest). Called when the scene becomes active again.
    func pruneExpiredRest(now suppliedNow: Date? = nil) {
        let now = suppliedNow ?? AppEnvironment.now
        reconcileLiveActivities(now: now)
    }

    /// Reconciles process-local state with ActivityKit's authoritative inventory. Called on
    /// cold launch and every foreground transition to clean legacy piles, dismiss elapsed
    /// cards, and recover at most one still-valid timer for the in-app pill and intents.
    func reconcileLiveActivities(now suppliedNow: Date? = nil) {
        guard !TestHooks.isUITesting else { return }
        let now = suppliedNow ?? AppEnvironment.now
        let plan = Self.reconciliationPlan(
            for: liveActivities.snapshots(),
            now: now,
            preferredActivityID: currentActivityID
        )

        if let keeper = plan.keeper {
            adopt(keeper, preservingNewerLocalDeadline: true)
        } else if activeRest?.endsAt ?? .distantPast <= now {
            endTask?.cancel()
            activeRest = nil
            currentActivityID = nil
            // Hygiene: the completion alert either already fired while suspended or is
            // past-dated (a past calendar trigger never fires); drop the pending request.
            restEndAlerts.cancelAlert()
        } else {
            // A future in-app rest can legitimately exist without a system activity when
            // Live Activities are disabled or a request failed. Keep the pill counting down.
            currentActivityID = nil
        }
        endLiveActivities(plan.activityIDsToEnd)
    }

    /// Ends every system-owned rest activity before requesting the latest desired timer.
    /// The generation check prevents rapid starts from resurrecting an older request after an
    /// `await` — only the final start is allowed to create a Live Activity.
    private func replaceLiveActivity(startedAt: Date) {
        guard !TestHooks.isUITesting else { return }
        liveActivityGeneration += 1
        let generation = liveActivityGeneration
        liveActivityTask?.cancel()
        liveActivityTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.liveActivityGeneration == generation else { return }
            let existingIDs = self.liveActivities.snapshots().map(\.id)
            for id in existingIDs {
                await self.liveActivities.endImmediately(activityID: id)
            }
            guard !Task.isCancelled,
                  self.liveActivityGeneration == generation,
                  self.liveActivities.activitiesEnabled,
                  let desiredRest = self.activeRest
            else { return }

            do {
                self.currentActivityID = try self.liveActivities.request(
                    exerciseName: desiredRest.exerciseName,
                    endsAt: desiredRest.endsAt,
                    staleDate: Self.liveActivityStaleDate(forRestEnding: desiredRest.endsAt),
                    startedAt: startedAt
                )
            } catch {
                // Live Activities can be unavailable or at the system limit. The in-app pill
                // remains useful, and every pre-existing activity has still been cleaned up.
                self.currentActivityID = nil
            }
        }
    }

    /// Pushes a new end date into the sole running activity. If a legacy pile is discovered,
    /// extras are removed before the keeper is updated.
    private func updateLiveActivity(endsAt: Date) {
        guard let currentActivityID else {
            // A start may still be waiting for old activities to end. It reads `activeRest`
            // immediately before requesting, so the eventual activity receives this deadline.
            return
        }
        let plan = Self.reconciliationPlan(
            for: liveActivities.snapshots(),
            now: AppEnvironment.now,
            preferredActivityID: currentActivityID
        )
        liveActivityGeneration += 1
        let generation = liveActivityGeneration
        let previousOperation = liveActivityTask
        liveActivityTask = Task { @MainActor [weak self] in
            // Do not overlap ActivityKit updates: cancellation cannot retract an update that
            // is already inside the framework. Waiting preserves +30s ordering under rapid taps.
            await previousOperation?.value
            guard let self, !Task.isCancelled, self.liveActivityGeneration == generation else { return }
            for id in plan.activityIDsToEnd where id != currentActivityID {
                await self.liveActivities.endImmediately(activityID: id)
            }
            guard !Task.isCancelled, self.liveActivityGeneration == generation else { return }
            await self.liveActivities.update(
                activityID: currentActivityID,
                endsAt: endsAt,
                staleDate: Self.liveActivityStaleDate(forRestEnding: endsAt)
            )
        }
    }

    private func scheduleAutoEnd(at endsAt: Date) {
        endTask = Task { [weak self] in
            let delay = max(0, endsAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            self?.completeRest(endingAt: endsAt)
        }
    }

    func completeRest(endingAt endsAt: Date) {
        // A canceled sleep can wake after a replacement. Never let timer A's completion end
        // timer B merely because the old task reached this method late.
        guard activeRest?.endsAt == endsAt else { return }
        activeRest = nil
        currentActivityID = nil
        // In-process completion means the app is running and (without a foreground-
        // presentation delegate) iOS would suppress the banner anyway; removing the pending
        // request keeps the notification center clean and can never double-alert.
        restEndAlerts.cancelAlert()
        endLiveActivities(liveActivities.snapshots().map(\.id))
    }

    private func adopt(
        _ snapshot: RestLiveActivitySnapshot,
        preservingNewerLocalDeadline: Bool = false
    ) {
        var endsAt = snapshot.endsAt
        if preservingNewerLocalDeadline,
           currentActivityID == snapshot.id,
           let activeRest {
            // ActivityKit updates are asynchronous. A foreground reconciliation or duplicate
            // cleanup must not roll a just-extended local timer back to stale system content.
            endsAt = max(activeRest.endsAt, snapshot.endsAt)
        }
        currentActivityID = snapshot.id
        beginRestSession(exerciseName: snapshot.exerciseName, endsAt: endsAt)
    }

    private func endLiveActivities(_ activityIDs: [String]) {
        guard !TestHooks.isUITesting, !activityIDs.isEmpty else { return }
        liveActivityGeneration += 1
        let generation = liveActivityGeneration
        liveActivityTask?.cancel()
        liveActivityTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.liveActivityGeneration == generation else { return }
            for id in activityIDs {
                await self.liveActivities.endImmediately(activityID: id)
            }
        }
    }

    /// Test hook for draining the serialized ActivityKit transition without sleeping.
    func waitForPendingLiveActivityOperation() async {
        await liveActivityTask?.value
    }

    // MARK: - Pure logic (unit-tested without the ActivityKit runtime)

    /// How long past the advertised end an un-ended activity may linger before the system
    /// marks it stale. `Text(timerInterval:)` renders 0:00 on its own with no update needed,
    /// so the grace only has to cover the normal end path: the auto-end (foreground) or the
    /// next foreground reconciliation dismisses the card well within a minute. Anything
    /// older is a genuinely missed end (process killed mid-rest), and rendering it stale is
    /// honest — a frozen card must not keep looking live.
    nonisolated static let liveActivityStaleGrace: TimeInterval = 60

    /// The `staleDate` carried by every request/update for a rest ending at `endsAt`.
    nonisolated static func liveActivityStaleDate(forRestEnding endsAt: Date) -> Date {
        endsAt.addingTimeInterval(liveActivityStaleGrace)
    }

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

    /// Chooses the single latest-created still-valid activity and marks every other system
    /// activity for immediate dismissal. Pre-2.3 activities have no creation timestamp, so
    /// their end date is the backward-compatible fallback. A known process-local activity wins.
    nonisolated static func reconciliationPlan(
        for snapshots: [RestLiveActivitySnapshot],
        now: Date,
        preferredActivityID: String? = nil
    ) -> RestLiveActivityReconciliation {
        let validSnapshots = snapshots.filter { $0.isOngoing && $0.endsAt > now }
        let keeper = validSnapshots.first { $0.id == preferredActivityID } ?? validSnapshots.max { lhs, rhs in
            switch (lhs.startedAt, rhs.startedAt) {
            case let (.some(lhsStart), .some(rhsStart)) where lhsStart != rhsStart:
                return lhsStart < rhsStart
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            default:
                if lhs.endsAt == rhs.endsAt { return lhs.id < rhs.id }
                return lhs.endsAt < rhs.endsAt
            }
        }
        let idsToEnd = snapshots
            .filter { $0.id != keeper?.id }
            .map(\.id)
            .sorted()
        return RestLiveActivityReconciliation(keeper: keeper, activityIDsToEnd: idsToEnd)
    }

    /// Rest surfaces stay out of UI-test runs (they'd overlay unrelated flows)
    /// unless a test opts in via `MARBLE_ENABLE_REST_PILL`.
    private static var isRestSurfaceEnabled: Bool {
        !TestHooks.isUITesting || TestHooks.enableRestPillInUITests
    }
}
