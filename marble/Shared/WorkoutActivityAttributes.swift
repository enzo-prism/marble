import ActivityKit
import Foundation

/// Shared value snapshot; no model or private notes enter the widget process.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    let sessionID: UUID
    let startedAt: Date
    nonisolated struct ContentState: Codable, Hashable {
        var title: String
        var exerciseName: String?
        var setCount: Int
        var restEndsAt: Date?
        var updatedAt: Date
    }
}
