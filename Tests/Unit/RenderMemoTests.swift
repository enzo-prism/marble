import XCTest
@testable import marble

final class RenderMemoTests: XCTestCase {
    func testRebuildsOnlyWhenKeyChanges() {
        let memo = RenderMemo<Int, Int>()
        var builds = 0
        func compute(_ key: Int) -> Int {
            memo.value(for: key) {
                builds += 1
                return key * 2
            }
        }

        XCTAssertEqual(compute(1), 2)
        XCTAssertEqual(builds, 1)

        // Same key → cached, no rebuild.
        XCTAssertEqual(compute(1), 2)
        XCTAssertEqual(compute(1), 2)
        XCTAssertEqual(builds, 1)

        // New key → rebuild.
        XCTAssertEqual(compute(2), 4)
        XCTAssertEqual(builds, 2)
    }

    func testSingleSlotCacheForgetsPreviousKey() {
        let memo = RenderMemo<Int, Int>()
        var builds = 0
        func compute(_ key: Int) -> Int {
            memo.value(for: key) {
                builds += 1
                return key
            }
        }

        _ = compute(1)
        _ = compute(2)
        // Returning to a previously-seen key is not cached (single slot).
        _ = compute(1)
        XCTAssertEqual(builds, 3)
    }

    func testStructKeyEquatableUsedForCaching() {
        struct Key: Equatable {
            let count: Int
            let stamp: Date
        }
        let memo = RenderMemo<Key, String>()
        var builds = 0
        let stamp = Date(timeIntervalSince1970: 1_000)

        func compute(_ key: Key) -> String {
            memo.value(for: key) {
                builds += 1
                return "\(key.count)"
            }
        }

        XCTAssertEqual(compute(Key(count: 3, stamp: stamp)), "3")
        XCTAssertEqual(compute(Key(count: 3, stamp: stamp)), "3")
        XCTAssertEqual(builds, 1)

        // Any field change invalidates the cache.
        XCTAssertEqual(compute(Key(count: 3, stamp: stamp.addingTimeInterval(1))), "3")
        XCTAssertEqual(builds, 2)
    }
}
