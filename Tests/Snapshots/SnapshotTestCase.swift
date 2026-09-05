import XCTest
@testable import marble

@MainActor
class SnapshotTestCase: XCTestCase {
    private var previousDraftNamespace: String?
    override func setUp() {
        super.setUp()
        previousDraftNamespace = ProcessInfo.processInfo.environment["MARBLE_DRAFT_NAMESPACE"]
        setenv("MARBLE_DRAFT_NAMESPACE", UUID().uuidString, 1)
        TestHooks.overrideNow = SnapshotFixtures.now
    }

    override func tearDown() {
        TestHooks.overrideNow = nil
        if let previousDraftNamespace {
            setenv("MARBLE_DRAFT_NAMESPACE", previousDraftNamespace, 1)
        } else {
            unsetenv("MARBLE_DRAFT_NAMESPACE")
        }
        super.tearDown()
    }

    func makeTabSelection(_ tab: AppTab) -> TabSelection {
        let selection = TabSelection()
        selection.selectLogMode(tab)
        return selection
    }
}
