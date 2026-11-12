import XCTest
@testable import marble

@MainActor
final class SharedWorkoutInboxTests: XCTestCase {
    func testShareCompletesAfterSuccessfulWrite() {
        switch SharedWorkoutInbox.SharePosting.disposition(saving: { }) {
        case .completeRequest: break
        case .cancelRequest: XCTFail("Successful write must complete the share request")
        }
    }

    func testShareCancelsAfterFailedWrite() {
        switch SharedWorkoutInbox.SharePosting.disposition(saving: { throw SharedWorkoutInbox.InboxError.full }) {
        case .completeRequest:
            XCTFail("A failed write must cancel the share request")
        case .cancelRequest(let error):
            XCTAssertEqual(error as? SharedWorkoutInbox.InboxError, .full)
        }
    }

    func testShareRetryDedupesMatchingInboxText() throws {
        let original = SharedWorkoutInbox.Item(id: UUID(), createdAt: Date(), text: "Bench 5x5 @ 185")
        let retry = try SharedWorkoutInbox.prepareSave(text: "  Bench 5x5 @ 185 \n", existing: [original])
        guard case .reuse(let item) = retry else {
            return XCTFail("Retry of the same share must reuse the existing inbox item")
        }
        XCTAssertEqual(item, original)

        let inserted = try SharedWorkoutInbox.prepareSave(text: "Squat 5x5 @ 225", existing: [original],
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, createdAt: original.createdAt)
        guard case .insert(let next) = inserted else {
            return XCTFail("A different workout must create a new inbox item")
        }
        XCTAssertEqual(next.text, "Squat 5x5 @ 225")
        XCTAssertNotEqual(next.id, original.id)

        let full = (0..<SharedWorkoutInbox.maximumItems).map { index in
            SharedWorkoutInbox.Item(id: UUID(), createdAt: Date(), text: "Workout \(index)")
        }
        XCTAssertThrowsError(try SharedWorkoutInbox.prepareSave(text: "Another", existing: full)) { error in
            XCTAssertEqual(error as? SharedWorkoutInbox.InboxError, .full)
        }
        let fullRetry = try SharedWorkoutInbox.prepareSave(text: full[0].text, existing: full)
        guard case .reuse(let kept) = fullRetry else {
            return XCTFail("A retry must reuse even when every inbox slot is occupied")
        }
        XCTAssertEqual(kept, full[0])
    }

    func testShareDedupeKeyIsStableForTheSameText() {
        let key = SharedWorkoutInbox.dedupeKey(for: "Bench 5x5")
        XCTAssertEqual(key, SharedWorkoutInbox.dedupeKey(for: "Bench 5x5"))
        XCTAssertNotEqual(key, SharedWorkoutInbox.dedupeKey(for: "Squat 5x5"))
        XCTAssertEqual(key.count, 64)
    }
}
