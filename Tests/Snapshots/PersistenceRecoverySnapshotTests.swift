import SwiftUI
import XCTest
@testable import marble

@MainActor
final class PersistenceRecoverySnapshotTests: SnapshotTestCase {
    func testTemporarilyUnavailable() {
        assertSnapshot(PersistenceUnavailableView(failure: .temporarilyUnavailable, retry: {}), named: "Storage_TemporarilyUnavailable")
    }

    func testDamagedStore() {
        assertSnapshot(PersistenceUnavailableView(failure: .damagedStore, retry: {}), named: "Storage_Damaged")
    }
}
