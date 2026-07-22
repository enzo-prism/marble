import Foundation
import ActivityKit

/// Shared Live Activity attributes for the between-sets rest timer.
///
/// **This file must be a member of BOTH targets:** the app (which starts/updates/ends the
/// activity) and the widget-extension (which renders it). ActivityKit matches the attributes
/// type by structure, so both targets compile their own identical copy.
///
/// `nonisolated` because `ActivityAttributes` / `ContentState` must be `Sendable`, and this
/// project defaults to main-actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`),
/// which would otherwise make the synthesized conformances main-actor-isolated — the same
/// reason `ExerciseMetricsProfile` is `nonisolated`.
nonisolated struct RestTimerAttributes: ActivityAttributes {
    /// The dynamic part of the activity, updated as the rest period progresses.
    nonisolated struct ContentState: Codable, Hashable {
        /// When the current rest period ends. Drives the live countdown (`Text(timerInterval:)`).
        var restEndsAt: Date
    }

    /// The exercise that was just logged — fixed for the life of the activity.
    var exerciseName: String

    /// Creation time identifies the newest rest independently of its duration. Optional so
    /// activities created by older Marble builds still decode and can be reconciled safely.
    var startedAt: Date?

    init(exerciseName: String, startedAt: Date? = nil) {
        self.exerciseName = exerciseName
        self.startedAt = startedAt
    }
}
