import XCTest
@testable import marble

@MainActor
final class NativeWorkoutControllerTests: XCTestCase {
    func testFinishForJournalIDIgnoresADifferentLiveSession() {
        let finished = UUID()
        let live = UUID()
        XCTAssertTrue(NativeWorkoutController.tracks(finished, liveSessionID: finished.uuidString))
        XCTAssertFalse(NativeWorkoutController.tracks(finished, liveSessionID: live.uuidString))
        XCTAssertFalse(NativeWorkoutController.tracks(finished, liveSessionID: nil))
    }
}
