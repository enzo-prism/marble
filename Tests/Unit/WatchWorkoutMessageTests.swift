import XCTest
@testable import marble

@MainActor
final class WatchWorkoutMessageTests: XCTestCase {
    private let requestID = UUID()
    private let pendingID = UUID()

    func testWatchKeepsRequestIDOnTransientFailure() throws {
        let retryable = WatchWorkoutResponse(succeeded: false, message: "Couldn't finish workout",
            snapshot: nil, retryable: true)
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: retryable))
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: nil))
    }

    func testWatchClearsRequestIDOnSuccessAndTerminalFailure() throws {
        let success = WatchWorkoutResponse(succeeded: true, message: "Workout already finished", snapshot: nil)
        XCTAssertTrue(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: success))

        let terminal = WatchWorkoutResponse(succeeded: false, message: "Workout changed. Refresh before logging.",
            snapshot: nil, retryable: false)
        XCTAssertTrue(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: terminal))

        let legacyFailure = try JSONDecoder().decode(WatchWorkoutResponse.self, from: Data(
            #"{"succeeded":false,"message":"Workout changed. Refresh before logging."}"#.utf8))
        XCTAssertTrue(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: legacyFailure))

        let original = WatchWorkoutResponse(succeeded: false, message: "Couldn't finish workout",
            snapshot: nil, retryable: true)
        let decoded = try JSONDecoder().decode(WatchWorkoutResponse.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded.retryable, true)
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: decoded))
    }

    func testReplyWithSuccessAndRetryableKeepsPendingRequest() {
        let both = WatchWorkoutResponse(succeeded: true, message: "Updated", snapshot: nil, retryable: true)
        XCTAssertFalse(both.shouldClearPendingRequest)
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: both))
    }

    func testWatchPendingRequestPolicyRequiresMatchingNonRefreshRequest() {
        let success = WatchWorkoutResponse(succeeded: true, message: "Updated", snapshot: nil)
        XCTAssertFalse(WatchPendingRequestPolicy.confirmsPendingRequest(
            action: .refresh, pendingID: requestID, requestID: requestID))
        XCTAssertFalse(WatchPendingRequestPolicy.confirmsPendingRequest(
            action: .finish, pendingID: pendingID, requestID: requestID))
        XCTAssertFalse(WatchPendingRequestPolicy.confirmsPendingRequest(
            action: .finish, pendingID: nil, requestID: requestID))
        XCTAssertTrue(WatchPendingRequestPolicy.confirmsPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID))
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .refresh, pendingID: requestID, requestID: requestID, response: success))
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: pendingID, requestID: requestID, response: success))
        XCTAssertFalse(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: nil, requestID: requestID, response: success))
        XCTAssertTrue(WatchPendingRequestPolicy.shouldClearPendingRequest(
            action: .finish, pendingID: requestID, requestID: requestID, response: success))
    }
}
