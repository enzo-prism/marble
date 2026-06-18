import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(useInMemory: Bool = false) -> ModelContainer {
        if useInMemory {
            return makeInMemoryContainer()
        }

        if TestHooks.resetDatabase {
            removeStoreFiles()
        }

        do {
            return try makePersistentContainer()
        } catch {
            // Opening the store failed — most likely an incompatible/failed migration.
            // Rather than crash-loop on launch with the user's data permanently
            // inaccessible, preserve the existing store as a backup (so a future build
            // could recover it) and recreate a fresh store so the app still launches.
            #if DEBUG
            print("ModelContainer open failed, attempting recovery: \(error)")
            #endif
            backupCorruptStore()
            do {
                return try makePersistentContainer()
            } catch {
                #if DEBUG
                print("ModelContainer recovery failed, falling back to in-memory store: \(error)")
                #endif
                return makeInMemoryContainer()
            }
        }
    }

    // MARK: - Container construction

    private static var schema: Schema {
        Schema(versionedSchema: MarbleSchemaV1.self)
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: MarbleMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: MarbleMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // An in-memory store has no on-disk state to be incompatible with, so a
            // failure here means the schema itself is invalid — genuinely unrecoverable.
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }

    // MARK: - Store files

    private static var storeDirectory: URL {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Marble", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var storeURL: URL {
        storeDirectory.appendingPathComponent("Marble.store")
    }

    /// SwiftData keeps the store as a SQLite file plus `-wal`/`-shm` sidecars.
    private static var allStoreFileURLs: [URL] {
        let base = storeURL
        return [
            base,
            base.deletingLastPathComponent().appendingPathComponent("Marble.store-wal"),
            base.deletingLastPathComponent().appendingPathComponent("Marble.store-shm")
        ]
    }

    private static func removeStoreFiles() {
        for url in allStoreFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves the existing store aside to `*.corrupt` so a failed migration doesn't
    /// destroy data outright; a later build could offer to recover from it.
    private static func backupCorruptStore() {
        let manager = FileManager.default
        for url in allStoreFileURLs where manager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("corrupt")
            try? manager.removeItem(at: backup)
            try? manager.moveItem(at: url, to: backup)
        }
    }
}
