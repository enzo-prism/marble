import XCTest
@testable import marble

@MainActor
final class WatchWorkoutMessageTests: XCTestCase {
    func testWatchKeepsRequestIDOnTransientFailure() throws {
        let retryable = WatchWorkoutResponse(succeeded: false, message: "Couldn't finish workout",
            snapshot: nil, retryable: true)
        XCTAssertFalse(retryable.shouldClearPendingRequest)
        XCTAssertFalse(WatchWorkoutResponse.shouldClearPendingRequest(for: retryable))
        XCTAssertFalse(WatchWorkoutResponse.shouldClearPendingRequest(for: nil))
    }

    func testWatchClearsRequestIDOnSuccessAndTerminalFailure() throws {
        let success = WatchWorkoutResponse(succeeded: true, message: "Workout already finished", snapshot: nil)
        XCTAssertTrue(success.shouldClearPendingRequest)
        XCTAssertTrue(WatchWorkoutResponse.shouldClearPendingRequest(for: success))

        let terminal = WatchWorkoutResponse(succeeded: false, message: "Workout changed. Refresh before logging.",
            snapshot: nil, retryable: false)
        XCTAssertTrue(terminal.shouldClearPendingRequest)

        let legacyFailure = try JSONDecoder().decode(WatchWorkoutResponse.self, from: Data(
            #"{"succeeded":false,"message":"Workout changed. Refresh before logging."}"#.utf8))
        XCTAssertTrue(legacyFailure.shouldClearPendingRequest)

        let original = WatchWorkoutResponse(succeeded: false, message: "Couldn't finish workout",
            snapshot: nil, retryable: true)
        let decoded = try JSONDecoder().decode(WatchWorkoutResponse.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded.retryable, true)
        XCTAssertFalse(decoded.shouldClearPendingRequest)
    }
}
