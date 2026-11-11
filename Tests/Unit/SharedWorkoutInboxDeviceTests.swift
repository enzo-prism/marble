import Foundation
import XCTest
@testable import marble

/// Exercises the actual shared keychain entitlement, atomic cross-process slots,
/// and exact-row deletion. Runs only in the isolated signed validation app.
@MainActor
final class SharedWorkoutInboxDeviceTests: XCTestCase {
    private var savedIDs: [UUID] = []
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation",
            "Requires the development-signed Marble Validation app on a physical device.")
        try XCTSkipUnless(SharedWorkoutInbox.items().isEmpty, "Preserving existing validation inbox contents.")
    }
    override func tearDownWithError() throws {
        for id in savedIDs { try SharedWorkoutInbox.remove(id: id) }
        savedIDs.removeAll()
        try super.tearDownWithError()
    }
    func testConcurrentHandoffsRespectCapacityAndRoundTrip() async throws {
        let items = await withTaskGroup(of: SharedWorkoutInbox.Item?.self) { group in
            for number in 0..<10 {
                group.addTask { try? SharedWorkoutInbox.save(text: "Validation workout \(number)\nBench 3x5 @ 185 lb") }
            }
            var results: [SharedWorkoutInbox.Item] = []
            for await item in group { if let item { results.append(item) } }
            return results
        }
        savedIDs = items.map(\.id)
        XCTAssertEqual(items.count, SharedWorkoutInbox.maximumItems)
        let reopened = try SharedWorkoutInbox.items()
        XCTAssertEqual(Set(reopened.map(\.id)), Set(savedIDs))
        XCTAssertEqual(Set(reopened.map(\.text)), Set(items.map(\.text)))
        XCTAssertThrowsError(try SharedWorkoutInbox.save(text: "No free slot"))
    }
    func testStaleReviewCannotDeleteAReusedSlot() throws {
        let original = try SharedWorkoutInbox.save(text: "Validation old workout")
        savedIDs.append(original.id)
        try SharedWorkoutInbox.remove(id: original.id)
        let replacement = try SharedWorkoutInbox.save(text: "Validation replacement workout")
        savedIDs.append(replacement.id)
        try SharedWorkoutInbox.remove(id: original.id)
        XCTAssertEqual(try SharedWorkoutInbox.items().map(\.id), [replacement.id])
    }
}
