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
    /// Transient companion failures keep the Watch retry ID. Missing values
    /// (older companions) are treated as non-retryable, matching prior replies.
    let retryable: Bool?

    init(succeeded: Bool, message: String, snapshot: WatchWorkoutSnapshot?, retryable: Bool? = nil) {
        self.succeeded = succeeded
        self.message = message
        self.snapshot = snapshot
        self.retryable = retryable
    }

    /// Drop the preserved Watch request ID only after a confirmed save or a
    /// failure that cannot succeed if the same request is sent again.
    var shouldClearPendingRequest: Bool {
        succeeded || !(retryable ?? false)
    }

    /// Undecodable and transport failures are transient: keep the request ID.
    static func shouldClearPendingRequest(for decoded: WatchWorkoutResponse?) -> Bool {
        decoded?.shouldClearPendingRequest ?? false
    }

    enum CodingKeys: String, CodingKey { case succeeded, message, snapshot, retryable }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        succeeded = try container.decode(Bool.self, forKey: .succeeded)
        message = try container.decode(String.self, forKey: .message)
        snapshot = try container.decodeIfPresent(WatchWorkoutSnapshot.self, forKey: .snapshot)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(succeeded, forKey: .succeeded)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
        try container.encodeIfPresent(retryable, forKey: .retryable)
    }
}
