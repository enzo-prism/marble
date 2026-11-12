import Foundation

nonisolated struct WatchWorkoutSnapshot: Codable, Sendable, Equatable {
    var sessionID: UUID?
    var title: String
    var startedAt: Date?
    var lastSetID: UUID?
    var exerciseName: String?
    var setCount: Int
    var restEndsAt: Date?
    var updatedAt: Date
}

nonisolated struct WatchWorkoutRequest: Codable, Sendable {
    enum Action: String, Codable, Sendable { case refresh, start, repeatSet, startRest, skipRest, finish }
    let id: UUID
    let action: Action
    let sessionID: UUID?
    let setID: UUID?
    let createdAt: Date
}

nonisolated struct WatchWorkoutResponse: Codable, Sendable {
    let succeeded: Bool
    let message: String
    let snapshot: WatchWorkoutSnapshot?
}
