import XCTest
@testable import marble

@MainActor
final class NativeWorkoutControllerTests: XCTestCase {
    override func tearDown() {
        NativeWorkoutController.shared.finishCurrentSessionCalls = 0
        UserDefaults.standard.removeObject(forKey: NativeWorkoutController.sessionKey)
        super.tearDown()
    }

    func testFinishForJournalIDIgnoresADifferentLiveSession() {
        let finished = UUID()
        let live = UUID()
        XCTAssertTrue(NativeWorkoutController.tracks(finished, liveSessionID: finished.uuidString))
        XCTAssertFalse(NativeWorkoutController.tracks(finished, liveSessionID: live.uuidString))
        XCTAssertFalse(NativeWorkoutController.tracks(finished, liveSessionID: nil))
        XCTAssertTrue(NativeWorkoutController.shouldFinish(journalID: finished, liveSessionID: finished.uuidString))
        XCTAssertFalse(NativeWorkoutController.shouldFinish(journalID: finished, liveSessionID: live.uuidString))
    }

    func testFinishForSkipsWhenLiveSessionBelongsToAnotherWorkout() async {
        let finished = UUID()
        let live = UUID()
        UserDefaults.standard.set(live.uuidString, forKey: NativeWorkoutController.sessionKey)
        NativeWorkoutController.shared.finishCurrentSessionCalls = 0
        await NativeWorkoutController.shared.finish(for: finished)
        XCTAssertEqual(NativeWorkoutController.shared.finishCurrentSessionCalls, 0)
        XCTAssertFalse(NativeWorkoutController.shouldFinish(journalID: finished, liveSessionID: live.uuidString))
    }
}
