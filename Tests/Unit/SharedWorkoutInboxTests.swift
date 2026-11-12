import XCTest
@testable import marble

@MainActor
final class SharedWorkoutInboxTests: XCTestCase {
    func testShareCompletesAfterSuccessfulWrite() {
        switch SharedWorkoutInbox.SharePosting.disposition(saving: { }) {
        case .completeRequest: break
        case .presentErrorThenCancel: XCTFail("Successful write must complete the share request")
        }
    }

    func testSharePresentsErrorThenCancelsAfterFailedWrite() {
        var presented: String?
        var cancelled: Error?
        var ack: (() -> Void)?
        SharedWorkoutInbox.SharePosting.performPost(
            saving: { throw SharedWorkoutInbox.InboxError.full },
            complete: { XCTFail("A failed write must not complete the share request") },
            presentError: { message, done in presented = message; ack = done },
            cancel: { error in cancelled = error },
            completion: SharedWorkoutInbox.SharePosting.CompletionGuard()
        )
        XCTAssertEqual(presented, SharedWorkoutInbox.InboxError.full.localizedDescription)
        XCTAssertNil(cancelled)
        ack?()
        XCTAssertEqual(cancelled as? SharedWorkoutInbox.InboxError, .full)
    }

    func testShareDoublePostCompletesOnce() {
        let completion = SharedWorkoutInbox.SharePosting.CompletionGuard()
        var completed = 0
        SharedWorkoutInbox.SharePosting.performPost(
            saving: { },
            complete: { completed += 1 },
            presentError: { _, _ in XCTFail("Successful write must not present an error") },
            cancel: { _ in XCTFail("Successful write must not cancel") },
            completion: completion
        )
        SharedWorkoutInbox.SharePosting.performPost(
            saving: { },
            complete: { completed += 1 },
            presentError: { _, _ in XCTFail("Successful write must not present an error") },
            cancel: { _ in XCTFail("Successful write must not cancel") },
            completion: completion
        )
        XCTAssertEqual(completed, 1)
    }

    func testShareRetryDedupesMatchingInboxText() throws {
        let now = Date()
        let original = SharedWorkoutInbox.Item(id: UUID(), createdAt: now, text: "Bench 5x5 @ 185")
        let retry = try SharedWorkoutInbox.prepareSave(text: "  Bench 5x5 @ 185 \n", existing: [original], now: now)
        guard case .reuse(let item) = retry else {
            return XCTFail("Retry of the same share must reuse the existing inbox item")
        }
        XCTAssertEqual(item, original)

        let inserted = try SharedWorkoutInbox.prepareSave(text: "Squat 5x5 @ 225", existing: [original],
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, createdAt: original.createdAt, now: now)
        guard case .insert(let next) = inserted else {
            return XCTFail("A different workout must create a new inbox item")
        }
        XCTAssertEqual(next.text, "Squat 5x5 @ 225")
        XCTAssertNotEqual(next.id, original.id)

        let full = (0..<SharedWorkoutInbox.maximumItems).map { index in
            SharedWorkoutInbox.Item(id: UUID(), createdAt: now, text: "Workout \(index)")
        }
        XCTAssertThrowsError(try SharedWorkoutInbox.prepareSave(text: "Another", existing: full, now: now)) { error in
            XCTAssertEqual(error as? SharedWorkoutInbox.InboxError, .full)
        }
        let fullRetry = try SharedWorkoutInbox.prepareSave(text: full[0].text, existing: full, now: now)
        guard case .reuse(let kept) = fullRetry else {
            return XCTFail("A retry must reuse even when every inbox slot is occupied")
        }
        XCTAssertEqual(kept, full[0])
    }

    func testSameTextAnHourLaterInsertsANewItem() throws {
        let now = Date()
        let original = SharedWorkoutInbox.Item(id: UUID(), createdAt: now, text: "Push day / Bench 3x5 @ 185")
        let later = now.addingTimeInterval(3600)
        let result = try SharedWorkoutInbox.prepareSave(
            text: original.text, existing: [original], createdAt: later, now: later
        )
        guard case .insert(let item) = result else {
            return XCTFail("The same undated routine a day later must not merge into yesterday's inbox item")
        }
        XCTAssertEqual(item.text, original.text)
        XCTAssertNotEqual(item.id, original.id)
        XCTAssertEqual(item.createdAt, later)

        let store = SharedWorkoutInbox.MemoryStore()
        _ = try SharedWorkoutInbox.save(text: original.text, now: now, using: store)
        _ = try SharedWorkoutInbox.save(text: original.text, now: later, using: store)
        XCTAssertEqual(store.items.count, 2)
    }

    func testSavingTheSameTextTwiceGivesOneItem() throws {
        let store = SharedWorkoutInbox.MemoryStore()
        let now = Date()
        let first = try SharedWorkoutInbox.save(text: "Bench 5x5 @ 185", now: now, using: store)
        let second = try SharedWorkoutInbox.save(text: "  Bench 5x5 @ 185 \n", now: now.addingTimeInterval(30), using: store)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.text, "Bench 5x5 @ 185")
    }

    func testSameTextAtRetryWindowBoundaryInsertsANewItem() throws {
        let now = Date()
        let original = SharedWorkoutInbox.Item(id: UUID(), createdAt: now, text: "Bench 5x5")
        let inside = now.addingTimeInterval(SharedWorkoutInbox.retryWindow - 1)
        let atBoundary = now.addingTimeInterval(SharedWorkoutInbox.retryWindow)
        let reuse = try SharedWorkoutInbox.prepareSave(text: original.text, existing: [original], now: inside)
        guard case .reuse(let kept) = reuse else {
            return XCTFail("599s is still inside the retry window")
        }
        XCTAssertEqual(kept, original)
        let result = try SharedWorkoutInbox.prepareSave(
            text: original.text, existing: [original], createdAt: atBoundary, now: atBoundary
        )
        guard case .insert(let item) = result else {
            return XCTFail("Exactly 600s must insert a new inbox item")
        }
        XCTAssertNotEqual(item.id, original.id)
    }

    func testReconcileBreaksEqualTimestampTiesByID() throws {
        let now = Date()
        let low = SharedWorkoutInbox.Item(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            createdAt: now,
            text: "Bench 5x5"
        )
        let high = SharedWorkoutInbox.Item(
            id: try XCTUnwrap(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")),
            createdAt: now,
            text: "Bench 5x5"
        )
        let result = SharedWorkoutInbox.reconcile(inserted: high, among: [high, low], now: now)
        XCTAssertEqual(result.keeper, low)
        XCTAssertEqual(result.extras.map(\.id), [high.id])
    }

    func testSaveReconcilesAfterAStaleFirstLoad() throws {
        let now = Date()
        let earlier = SharedWorkoutInbox.Item(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            createdAt: now,
            text: "Bench 5x5"
        )
        let store = StaleFirstLoadInboxStore()
        store.planted = earlier
        let saved = try SharedWorkoutInbox.save(text: "Bench 5x5", now: now.addingTimeInterval(1), using: store)
        XCTAssertEqual(saved.id, earlier.id)
        XCTAssertEqual(store.items.map(\.id), [earlier.id])
    }

    func testShareCancelGoesThroughCompletionGuard() {
        let completion = SharedWorkoutInbox.SharePosting.CompletionGuard()
        var cancelled = 0
        var acks: [() -> Void] = []
        for _ in 0..<2 {
            SharedWorkoutInbox.SharePosting.performPost(
                saving: { throw SharedWorkoutInbox.InboxError.full },
                complete: { XCTFail("A failed write must not complete") },
                presentError: { _, done in acks.append(done) },
                cancel: { _ in cancelled += 1 },
                completion: completion
            )
        }
        acks.forEach { $0() }
        XCTAssertEqual(cancelled, 1)
    }

    func testReconcileRemovesLaterDuplicateFromADoublePost() {
        let now = Date()
        let first = SharedWorkoutInbox.Item(id: UUID(), createdAt: now, text: "Bench 5x5")
        let second = SharedWorkoutInbox.Item(id: UUID(), createdAt: now.addingTimeInterval(1), text: "Bench 5x5")
        let result = SharedWorkoutInbox.reconcile(inserted: second, among: [first, second], now: now.addingTimeInterval(1))
        XCTAssertEqual(result.keeper, first)
        XCTAssertEqual(result.extras.map(\.id), [second.id])
    }

    func testShareDedupeKeyIsStableForTheSameText() {
        let key = SharedWorkoutInbox.dedupeKey(for: "Bench 5x5")
        XCTAssertEqual(key, SharedWorkoutInbox.dedupeKey(for: "Bench 5x5"))
        XCTAssertNotEqual(key, SharedWorkoutInbox.dedupeKey(for: "Squat 5x5"))
        XCTAssertEqual(key.count, 64)
    }
}

final class StaleFirstLoadInboxStore: SharedWorkoutInbox.Storage, @unchecked Sendable {
    nonisolated(unsafe) var items: [SharedWorkoutInbox.Item] = []
    nonisolated(unsafe) var planted: SharedWorkoutInbox.Item?
    nonisolated func load() throws -> [SharedWorkoutInbox.Item] { items }
    nonisolated func insert(_ item: SharedWorkoutInbox.Item) throws {
        if let planted { items.append(planted) }
        items.append(item)
    }
    nonisolated func delete(id: UUID) throws { items.removeAll { $0.id == id } }
}
