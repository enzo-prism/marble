import XCTest
@testable import marble

/// Covers the pure decision/timing logic of the rest-timer Live Activity. The ActivityKit
/// runtime (requesting/ending activities) needs a device and user authorization, so it isn't
/// unit-testable; these tests pin the behaviour that decides *whether* and *until when* a
/// timer runs.
final class RestActivityControllerTests: XCTestCase {
    func testStartsOnlyWhenRestIsPositive() {
        XCTAssertTrue(RestActivityController.shouldStart(restSeconds: 90))
        XCTAssertTrue(RestActivityController.shouldStart(restSeconds: 1))
        XCTAssertFalse(RestActivityController.shouldStart(restSeconds: 0))
        XCTAssertFalse(RestActivityController.shouldStart(restSeconds: -30))
    }

    func testRestEndDateAddsRestToNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RestActivityController.restEndDate(restSeconds: 90, now: now), now.addingTimeInterval(90))
        XCTAssertEqual(RestActivityController.restEndDate(restSeconds: 0, now: now), now)
    }
}
