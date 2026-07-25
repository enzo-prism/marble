import XCTest
@testable import marble

@MainActor
final class ComponentGallerySnapshotTests: SnapshotTestCase {
    func testComponentGallery() {
        #if DEBUG
        let view = ComponentGalleryView()
        assertSnapshot(view, named: "ComponentGallery")
        #else
        XCTSkip("Component gallery available in DEBUG only")
        #endif
    }
}

