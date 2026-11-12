import XCTest
import Synchronization
@testable import marble

@MainActor
final class WorkoutDictationTests: MarbleTestCase {
    func testCancelledStartDoesNotRequestPermission() async {
        var requests = 0
        let capture = WorkoutDictation(requestRecordPermission: { requests += 1; return false })
        let starting = Task { await capture.start() }
        starting.cancel()
        await starting.value
        XCTAssertEqual(requests, 0)
        XCTAssertNil(capture.errorMessage)
    }

    func testStoppedPreparationIgnoresDelayedPermissionResponse() async {
        let requested = expectation(description: "Permission requested")
        var response: CheckedContinuation<Bool, Never>?
        let capture = WorkoutDictation(requestRecordPermission: {
            await withCheckedContinuation { continuation in
                response = continuation
                requested.fulfill()
            }
        })
        let starting = Task { await capture.start() }
        await fulfillment(of: [requested], timeout: 5)
        XCTAssertTrue(capture.isPreparing)
        await capture.stop()
        XCTAssertFalse(capture.isPreparing)
        // False also keeps a regressed implementation from reaching hardware
        // or asset APIs: the assertion detects its stale permission error.
        response?.resume(returning: false)
        await starting.value
        XCTAssertFalse(capture.isRecording)
        XCTAssertNil(capture.errorMessage)
    }

    func testOldPreparationCannotClearNewPreparationState() async {
        let firstRequested = expectation(description: "First permission request")
        let secondRequested = expectation(description: "Second permission request")
        var responses: [CheckedContinuation<Bool, Never>] = []
        let capture = WorkoutDictation(requestRecordPermission: {
            await withCheckedContinuation { continuation in
                responses.append(continuation)
                if responses.count == 1 { firstRequested.fulfill() }
                else { secondRequested.fulfill() }
            }
        })
        let first = Task { await capture.start() }
        await fulfillment(of: [firstRequested], timeout: 5)
        await capture.stop()
        let second = Task { await capture.start() }
        await fulfillment(of: [secondRequested], timeout: 5)
        guard responses.count == 2 else {
            capture.cancel()
            responses.forEach { $0.resume(returning: false) }
            first.cancel(); second.cancel()
            return XCTFail("Both requests must be independently suspended")
        }
        responses[0].resume(returning: false)
        await first.value
        XCTAssertTrue(capture.isPreparing)
        capture.cancel()
        responses[1].resume(returning: false)
        await second.value
        XCTAssertFalse(capture.isPreparing)
        XCTAssertFalse(capture.isRecording)
        XCTAssertNil(capture.errorMessage)
    }

    func testDeniedPermissionKeepsTypingAvailable() async {
        let capture = WorkoutDictation(requestRecordPermission: { false })
        await capture.start()
        XCTAssertTrue(capture.errorMessage?.contains("Microphone access is off") == true)
        XCTAssertFalse(capture.isRecording)
        XCTAssertFalse(capture.isPreparing)
    }

    func testCancelledAudioActivationDoesNotTouchSystemAudio() async {
        let calls = Mutex<[String]>([])
        let session = WorkoutDictationAudioSession(
            activate: { calls.withLock { $0.append("activate") } },
            deactivate: { calls.withLock { $0.append("deactivate") } }
        )
        await session.deactivate(generation: 1)
        do {
            try await session.activate(generation: 1)
            XCTFail("A cancelled setup must not reactivate audio")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls.withLock { $0 }, [])
    }

    func testLateStopDoesNotDeactivateNewAudioOwner() async throws {
        let calls = Mutex<[String]>([])
        let session = WorkoutDictationAudioSession(
            activate: { calls.withLock { $0.append("activate") } },
            deactivate: { calls.withLock { $0.append("deactivate") } }
        )
        try await session.activate(generation: 1)
        try await session.activate(generation: 3)
        await session.deactivate(generation: 1)
        XCTAssertEqual(calls.withLock { $0 }, ["activate", "activate"])
        await session.deactivate(generation: 3)
        XCTAssertEqual(calls.withLock { $0 }, ["activate", "activate", "deactivate"])
    }

    func testOldActivationCannotReplaceNewAudioOwner() async throws {
        let calls = Mutex<[String]>([])
        let session = WorkoutDictationAudioSession(
            activate: { calls.withLock { $0.append("activate") } },
            deactivate: { calls.withLock { $0.append("deactivate") } }
        )
        try await session.activate(generation: 3)
        do {
            try await session.activate(generation: 1)
            XCTFail("An older request must not replace the current owner")
        } catch { XCTAssertTrue(error is CancellationError) }
        await session.deactivate(generation: 1)
        await session.deactivate(generation: 3)
        XCTAssertEqual(calls.withLock { $0 }, ["activate", "deactivate"])
    }
}
