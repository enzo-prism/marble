import Foundation
import SwiftData
import XCTest
@testable import marble

/// Exercises the on-disk store lifecycle and the self-recovery path in
/// `PersistenceController.makeRecoveringContainer(at:)` against a throwaway store in a
/// unique temp directory — never the real Application Support store.
@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    // `nonisolated(unsafe)` so the nonisolated XCTest setUp/tearDown overrides can
    // set them without sending `self` across isolation (Swift 6 language mode).
    // Only ever touched on the main thread, one test at a time.
    nonisolated(unsafe) private var tempDirectory: URL!
    nonisolated(unsafe) private var storeURL: URL!

    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marble-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storeURL = tempDirectory.appendingPathComponent("Marble.store")
        clearRecoveryNotice()
    }

    nonisolated override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        clearRecoveryNotice()
        try super.tearDownWithError()
    }

    /// Data written through one container is readable after the store is reopened — the
    /// basic guarantee a real migration/round-trip depends on.
    func testOnDiskRoundTripPersistsData() throws {
        try autoreleasepool {
            let container = try PersistenceController.makeRecoveringContainer(at: storeURL)
            let context = ModelContext(container)
            context.insert(Exercise(name: "Squat", category: .other, metrics: .weightAndRepsRequired, defaultRestSeconds: 120))
            try context.save()
        }

        let reopened = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(reopened)
        let names = try context.fetch(FetchDescriptor<Exercise>()).map(\.name)
        XCTAssertEqual(names, ["Squat"])
    }

    func testUnreadableStoreFailsWithoutReplacingUserData() throws {
        let bytes = Data(repeating: 0xFF, count: 8192)
        try bytes.write(to: storeURL)
        XCTAssertThrowsError(try PersistenceController.makeRecoveringContainer(at: storeURL))
        XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path))
    }

    func testTemporaryOpenFailuresPreserveEntireStoreSetAndNeverRetryOrFallback() throws {
        for code in [13, 28, 16] {
            let files = PersistenceController.sidecarURLs(for: storeURL)
            let bytes = Data("preserve all store files".utf8)
            for file in files { try bytes.write(to: file) }
            var attempts = 0
            XCTAssertThrowsError(try PersistenceController.makeRecoveringContainer(at: storeURL) { _ in
                attempts += 1
                throw NSError(domain: NSPOSIXErrorDomain, code: code)
            }) { error in
                XCTAssertEqual(error as? PersistenceOpenFailure, .temporarilyUnavailable)
            }
            XCTAssertEqual(attempts, 1)
            for file in files { XCTAssertEqual(try Data(contentsOf: file), bytes) }
        }
    }

    func testNestedTransientErrorWinsOverMigrationWrapper() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134110, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)
        ])
        XCTAssertEqual(PersistenceOpenFailure.classify(error), .temporarilyUnavailable)
        XCTAssertEqual(PersistenceOpenFailure.classify(NSError(domain: "NSSQLiteErrorDomain", code: 26)), .damagedStore)
        XCTAssertEqual(PersistenceOpenFailure.classify(NSError(domain: NSCocoaErrorDomain, code: 134110)), .incompatibleStore)
        XCTAssertEqual(PersistenceOpenFailure.classify(NSError(domain: "unknown", code: 1)), .unknown)
    }

    func testRetryCanOpenSameStoreAfterTemporaryFailure() throws {
        XCTAssertThrowsError(try PersistenceController.makeRecoveringContainer(at: storeURL) { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 13)
        })
        let container = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(container)
        context.insert(Exercise(name: "Recovered", category: .other, metrics: .repsOnlyRequired, defaultRestSeconds: 60))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testMigratesV1StoreToV2WithoutRecoveryOrDataLoss() throws {
        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: MarbleSchemaV1.self)
            let configuration = ModelConfiguration(schema: v1Schema, url: storeURL)
            let container = try ModelContainer(for: v1Schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Exercise(name: "Legacy Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120))
            try context.save()
        }

        let migrated = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(migrated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.name), ["Legacy Squat"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path))
    }

    func testAdditiveV2UsesAutomaticMigrationWithoutExplicitStage() {
        XCTAssertTrue(
            MarbleMigrationPlan.stages.isEmpty,
            "V2 only adds WorkoutSession; a redundant explicit stage crashes real V1 Release stores"
        )
    }

    func testMigratesV2StoreToV3AndPreservesTrainingData() throws {
        try autoreleasepool {
            let v2Schema = Schema(versionedSchema: MarbleSchemaV2.self)
            let configuration = ModelConfiguration(schema: v2Schema, url: storeURL)
            let container = try ModelContainer(for: v2Schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Exercise(name: "Legacy Sprint", category: .power, metrics: .distanceAndDurationRequired, defaultRestSeconds: 120))
            try context.save()
        }

        let migrated = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(migrated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.name), ["Legacy Sprint"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path))
    }

    /// The gate the roadmap asked for and 2.2 shipped without: V5 is the
    /// schema on disk for every 2.2 install, so the **recovery container** —
    /// not just a bare `ModelContainer` (`SchemaV5MigrationTests` covers that) —
    /// has to open a real V4 store additively, keep its training data, and
    /// leave no `.corrupt` backup behind. A V4→V5 migration that trips the
    /// recovery path would silently reset a shipping user's journal, which is
    /// exactly how build 35 failed.
    func testMigratesV4StoreToV5WithoutRecoveryOrDataLoss() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
        let exerciseID = UUID()
        let entryID = UUID()
        let sessionID = UUID()

        // Seeded row by row rather than through `TestFixtures`: that helper's
        // `clear` fetches `BodyMetricEntry`, which does not exist in a V4
        // container.
        try autoreleasepool {
            let v4Schema = Schema(versionedSchema: MarbleSchemaV4.self)
            let configuration = ModelConfiguration(schema: v4Schema, url: storeURL)
            let container = try ModelContainer(for: v4Schema, configurations: [configuration])
            let context = ModelContext(container)
            let exercise = Exercise(
                id: exerciseID,
                name: "Legacy Back Squat",
                category: .quads,
                metrics: .weightAndRepsRequired,
                defaultRestSeconds: 180
            )
            context.insert(exercise)
            context.insert(SetEntry(
                id: entryID,
                exercise: exercise,
                performedAt: fixedNow,
                weight: 140,
                reps: 5,
                restAfterSeconds: 180
            ))
            context.insert(WorkoutSession(
                id: sessionID,
                title: "Legacy Session",
                startedAt: fixedNow
            ))
            try context.save()
        }

        let migrated = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.id), [exerciseID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id), [entryID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id), [sessionID])
        // V5 is purely additive: the new table exists and is empty.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path),
            "A V4 store must migrate, not fall into the corrupt-store recovery path"
        )

        // And the migrated store accepts the new model, so the weigh-in flow
        // works for an upgrading user rather than only a fresh install.
        context.insert(BodyMetricEntry(measuredAt: fixedNow, weightKilograms: 82.5))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetricEntry>()), 1)
    }

    func testMigratesRealisticPopulatedV1StoreToV2() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
        var expectedExercises = 0
        var expectedSets = 0
        var expectedSupplements = 0
        var expectedPlans = 0
        var expectedImports = 0

        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: MarbleSchemaV1.self)
            let configuration = ModelConfiguration(schema: v1Schema, url: storeURL)
            let container = try ModelContainer(for: v1Schema, configurations: [configuration])
            let context = ModelContext(container)
            TestFixtures.seed(in: context, now: fixedNow)
            try context.save()
            expectedExercises = try context.fetchCount(FetchDescriptor<Exercise>())
            expectedSets = try context.fetchCount(FetchDescriptor<SetEntry>())
            expectedSupplements = try context.fetchCount(FetchDescriptor<SupplementEntry>())
            expectedPlans = try context.fetchCount(FetchDescriptor<SplitPlan>())
            expectedImports = try context.fetchCount(FetchDescriptor<ImportedWorkout>())
        }

        let migrated = try PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), expectedExercises)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), expectedSets)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SupplementEntry>()), expectedSupplements)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SplitPlan>()), expectedPlans)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportedWorkout>()), expectedImports)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path))
    }

    func testRepeatedFailedOpensNeverMoveOriginalOrOverwriteOlderRecovery() throws {
        let bytes = Data(repeating: 0xA1, count: 8192)
        let older = storeURL.appendingPathExtension("corrupt")
        try Data("older backup".utf8).write(to: older)
        try bytes.write(to: storeURL)
        for _ in 0..<2 {
            XCTAssertThrowsError(try PersistenceController.makeRecoveringContainer(at: storeURL))
            XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
            XCTAssertEqual(try Data(contentsOf: older), Data("older backup".utf8))
        }
    }

    func testRecoveryCopyPreservesStoreAndAllSidecarsWithoutOverwritingOlderCopy() throws {
        let files = PersistenceController.sidecarURLs(for: storeURL)
        for (index, file) in files.enumerated() {
            try Data(repeating: UInt8(index + 1), count: 256).write(to: file)
        }
        let destination = tempDirectory.appendingPathComponent("copies")
        let first = try PersistenceRecoveryCopy.prepareCopy(at: storeURL, destinationDirectory: destination)
        let second = try PersistenceRecoveryCopy.prepareCopy(at: storeURL, destinationDirectory: destination)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let package = first.deletingPathExtension()
        for (index, file) in files.enumerated() {
            let expected = Data(repeating: UInt8(index + 1), count: 256)
            XCTAssertEqual(try Data(contentsOf: file), expected)
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(file.lastPathComponent)), expected)
        }
    }

    func testRecoveryCopyFailureLeavesSourcesUntouched() throws {
        let bytes = Data("original".utf8)
        try bytes.write(to: storeURL)
        let blockedDestination = tempDirectory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockedDestination)
        XCTAssertThrowsError(try PersistenceRecoveryCopy.prepareCopy(at: storeURL, destinationDirectory: blockedDestination))
        XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
    }

    func testInterruptedSidecarCopyKeepsOriginalSetAndPublishesNoArchive() throws {
        let files = PersistenceController.sidecarURLs(for: storeURL)
        let bytes = Data("intact source".utf8)
        for file in files { try bytes.write(to: file) }
        let destination = tempDirectory.appendingPathComponent("copies")
        var copies = 0
        XCTAssertThrowsError(try PersistenceRecoveryCopy.prepareCopy(at: storeURL, destinationDirectory: destination) { source, target in
            copies += 1
            if copies == 2 { throw NSError(domain: NSPOSIXErrorDomain, code: 28) }
            try FileManager.default.copyItem(at: source, to: target)
        })
        for file in files { XCTAssertEqual(try Data(contentsOf: file), bytes) }
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".partial") })
    }

    func testChangedSourceDuringCopyIsRejected() throws {
        try Data("before".utf8).write(to: storeURL)
        let destination = tempDirectory.appendingPathComponent("copies")
        XCTAssertThrowsError(try PersistenceRecoveryCopy.prepareCopy(at: storeURL, destinationDirectory: destination) { source, target in
            try FileManager.default.copyItem(at: source, to: target)
            try Data("after".utf8).write(to: source)
        }) { error in
            guard case PersistenceRecoveryCopy.CopyError.sourceChanged = error else {
                return XCTFail("Expected changed-source rejection, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("after".utf8))
    }

    /// `nonisolated`: called from the nonisolated setUp/tearDown overrides. It
    /// only reads key strings and writes `UserDefaults`.
    nonisolated private func clearRecoveryNotice() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PersistenceRecoveryNotice.recoveryDateKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.recoveryBackupNameKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.acknowledgedKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.lastSuccessfulRestoreKey)
    }
}
