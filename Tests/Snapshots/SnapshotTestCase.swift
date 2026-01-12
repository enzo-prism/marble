import XCTest
import SnapshotTesting
@testable import marble

class SnapshotTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        isRecording = SnapshotRecording.isEnabled
        TestHooks.overrideNow = SnapshotFixtures.now
    }

    override func tearDown() {
        TestHooks.overrideNow = nil
        super.tearDown()
    }
}
