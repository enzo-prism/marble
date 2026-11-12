import Foundation
import Synchronization
import XCTest
@testable import marble

@MainActor
final class NotificationDeliveryTests: MarbleTestCase {
    func testSynchronousRemovalRunsAwayFromMainThreadAndKeepsItsScope() async throws {
        let observation = Mutex<(identifiers: [String], mainThread: Bool)?>(nil)
        let identifiers = ["marble.restTimer.restComplete"]
        await NotificationDelivery.removePending(identifiers: identifiers) { received in
            observation.withLock { $0 = (received, Thread.isMainThread) }
        }
        let result = try XCTUnwrap(observation.withLock { $0 })
        XCTAssertEqual(result.identifiers, identifiers)
        XCTAssertFalse(result.mainThread, "Synchronous notification XPC must never stall the UI thread.")
    }
}
