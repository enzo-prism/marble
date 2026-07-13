import Foundation
import SwiftData
import XCTest
@testable import marble

/// Exercises the on-disk store lifecycle and the self-recovery path in
/// `PersistenceController.makeRecoveringContainer(at:)` against a throwaway store in a
/// unique temp directory — never the real Application Support store.
@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    private var tempDirectory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marble-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storeURL = tempDirectory.appendingPathComponent("Marble.store")
        clearRecoveryNotice()
    }

    override func tearDownWithError() throws {
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
            let container = PersistenceController.makeRecoveringContainer(at: storeURL)
            let context = ModelContext(container)
            context.insert(Exercise(name: "Squat", category: .other, metrics: .weightAndRepsRequired, defaultRestSeconds: 120))
            try context.save()
        }

        let reopened = PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(reopened)
        let names = try context.fetch(FetchDescriptor<Exercise>()).map(\.name)
        XCTAssertEqual(names, ["Squat"])
    }

    /// An unreadable store is moved aside to `*.corrupt` and replaced with a fresh, usable
    /// store instead of crashing — the launch-survival guarantee.
    func testRecoversFromCorruptStoreAndPreservesBackup() throws {
        // Seed a valid store, then release the container so its files are flushed/closed.
        try autoreleasepool {
            let container = PersistenceController.makeRecoveringContainer(at: storeURL)
            let context = ModelContext(container)
            context.insert(Exercise(name: "Bench", category: .other, metrics: .weightAndRepsRequired, defaultRestSeconds: 90))
            try context.save()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        // Make the store unreadable: overwrite the main file with non-SQLite bytes and drop
        // the sidecars so there's no valid WAL to recover from.
        try Data(repeating: 0xFF, count: 8192).write(to: storeURL)
        for sidecar in ["Marble.store-wal", "Marble.store-shm"] {
            try? FileManager.default.removeItem(at: tempDirectory.appendingPathComponent(sidecar))
        }

        // Reopen: recovery should back up the corrupt store and create a fresh one.
        let recovered = PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(recovered)

        let backupURL = storeURL.appendingPathExtension("corrupt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path),
            "corrupt store should be preserved as \(backupURL.lastPathComponent)"
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty, "recovered store should be fresh")

        // The fresh store is fully usable.
        context.insert(Exercise(name: "Fresh", category: .other, metrics: .repsOnlyRequired, defaultRestSeconds: 60))
        XCTAssertNoThrow(try context.save())
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

        let migrated = PersistenceController.makeRecoveringContainer(at: storeURL)
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

        let migrated = PersistenceController.makeRecoveringContainer(at: storeURL)
        let context = ModelContext(migrated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(\.name), ["Legacy Sprint"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.appendingPathExtension("corrupt").path))
    }

    func testRepeatedRecoveryNeverOverwritesOlderBackup() throws {
        let olderBytes = Data(repeating: 0xA1, count: 8192)
        try olderBytes.write(to: storeURL)
        try autoreleasepool {
            _ = PersistenceController.makeRecoveringContainer(at: storeURL)
        }

        let originalBackupURL = storeURL.appendingPathExtension("corrupt")
        XCTAssertEqual(try Data(contentsOf: originalBackupURL), olderBytes)

        try Data(repeating: 0xB2, count: 8192).write(to: storeURL)
        for sidecar in ["Marble.store-wal", "Marble.store-shm"] {
            try? FileManager.default.removeItem(at: tempDirectory.appendingPathComponent(sidecar))
        }
        try autoreleasepool {
            _ = PersistenceController.makeRecoveringContainer(at: storeURL)
        }

        XCTAssertEqual(try Data(contentsOf: originalBackupURL), olderBytes)
        let recoveryNames = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
            .filter { $0.hasPrefix("Marble.store.corrupt-") }
        XCTAssertEqual(recoveryNames.count, 1)
    }

    private func clearRecoveryNotice() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PersistenceRecoveryNotice.recoveryDateKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.recoveryBackupNameKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.acknowledgedKey)
        defaults.removeObject(forKey: PersistenceRecoveryNotice.lastSuccessfulRestoreKey)
    }
}
