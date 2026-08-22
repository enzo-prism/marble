import XCTest
import SnapshotTesting
@testable import marble

@MainActor
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

    func makeTabSelection(_ tab: AppTab) -> TabSelection {
        let selection = TabSelection()
        selection.selectLogMode(tab)
        return selection
    }
}
