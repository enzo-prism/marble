import Foundation
import SwiftData
import XCTest
@testable import marble

/// Exercises the auto-import state machine with an injected fetch and an
/// isolated `UserDefaults` suite — no ActivityKit/HealthKit runtime involved.
@MainActor
final class HealthAutoImportServiceTests: MarbleTestCase {
    /// Fresh, isolated defaults per test (XCTestCase's setUp/tearDown are
    /// nonisolated, so state lives inside each MainActor test body instead).
    private func makeDefaults() -> UserDefaults {
        let suiteName = "HealthAutoImportServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func record(externalID: String = "hk-auto-1") -> WorkoutImportRecord {
        WorkoutImportRecord(
            source: .appleHealth,
            externalID: externalID,
            date: now,
            title: "Running",
            kind: .running,
            distanceMeters: 5000,
            durationSeconds: 1800,
            calories: 300,
            averageHeartRate: 150
        )
    }

    func testEnableStampsSinceDateAndDisableClearsIt() {
        let defaults = makeDefaults()
        let service = HealthAutoImportService(defaults: defaults, now: { self.now }) { _, _ in ([], nil) }

        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.enabledSince)

        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.enabledSince, now)

        service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.enabledSince, "Disabling must clear the window so a re-enable starts fresh")
    }

    func testSyncDoesNothingWhenDisabled() async {
        let defaults = makeDefaults()
        var fetchCount = 0
        let service = HealthAutoImportService(defaults: defaults, now: { self.now }) { _, _ in
            fetchCount += 1
            return ([], nil)
        }

        await service.syncIfEnabled(into: makeInMemoryContext())

        XCTAssertEqual(fetchCount, 0)
    }

    func testSyncImportsNewRecordsAndPersistsAnchor() async throws {
        let defaults = makeDefaults()
        let anchorToken = Data("anchor-1".utf8)
        let service = HealthAutoImportService(defaults: defaults, now: { self.now }) { anchor, notBefore in
            XCTAssertNil(anchor, "First sync starts with no anchor")
            XCTAssertEqual(notBefore, self.now, "The window opens when the user enabled auto-import")
            return ([self.record()], anchorToken)
        }
        service.setEnabled(true)
        let context = makeInMemoryContext()

        await service.syncIfEnabled(into: context)

        let imported = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.calories, 300)
        XCTAssertEqual(service.lastResult?.importedWorkouts, 1)
        XCTAssertEqual(defaults.data(forKey: "marble.health.autoImportAnchor"), anchorToken)
    }

    func testSecondSyncPassesPersistedAnchorAndSkipsKnownWorkouts() async throws {
        let defaults = makeDefaults()
        var receivedAnchors: [Data?] = []
        let service = HealthAutoImportService(defaults: defaults, now: { self.now }) { anchor, _ in
            receivedAnchors.append(anchor)
            return ([self.record()], Data("anchor-\(receivedAnchors.count)".utf8))
        }
        service.setEnabled(true)
        let context = makeInMemoryContext()

        await service.syncIfEnabled(into: context)
        await service.syncIfEnabled(into: context)

        XCTAssertEqual(receivedAnchors.count, 2)
        XCTAssertNil(receivedAnchors[0])
        XCTAssertEqual(receivedAnchors[1], Data("anchor-1".utf8))
        let imported = try context.fetch(FetchDescriptor<ImportedWorkout>())
        XCTAssertEqual(imported.count, 1, "The dedup ledger makes a replayed workout a no-op")
    }

    func testFetchFailureKeepsAnchorForRetry() async {
        let defaults = makeDefaults()
        defaults.set(Data("kept".utf8), forKey: "marble.health.autoImportAnchor")
        defaults.set(true, forKey: "marble.health.autoImportEnabled")
        defaults.set(now, forKey: "marble.health.autoImportSince")
        struct FetchError: Error {}
        let service = HealthAutoImportService(defaults: defaults, now: { self.now }) { _, _ in
            throw FetchError()
        }

        await service.syncIfEnabled(into: makeInMemoryContext())

        XCTAssertEqual(defaults.data(forKey: "marble.health.autoImportAnchor"), Data("kept".utf8))
        XCTAssertNil(service.lastResult)
    }
}
