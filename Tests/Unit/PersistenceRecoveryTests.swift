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
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
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
}
