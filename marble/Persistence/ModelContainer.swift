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

        return makeRecoveringContainer(at: storeURL)
    }

    /// Opens the on-disk store at `url`, recovering instead of crash-looping when it can't
    /// be read (most often an incompatible/failed migration): the unreadable store is moved
    /// aside to `*.corrupt` (so a future build could recover the user's data), a fresh store
    /// is created, and if even that fails it falls back to an in-memory store so the app
    /// still launches. Internal so tests can drive the recovery path against a throwaway
    /// store URL rather than the real Application Support store.
    static func makeRecoveringContainer(at url: URL) -> ModelContainer {
        do {
            return try makePersistentContainer(at: url)
        } catch {
            #if DEBUG
            print("ModelContainer open failed, attempting recovery: \(error)")
            #endif
            backupCorruptStore(at: url)
            do {
                return try makePersistentContainer(at: url)
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

    private static func makePersistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
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
    private static func sidecarURLs(for base: URL) -> [URL] {
        let directory = base.deletingLastPathComponent()
        let name = base.lastPathComponent
        return [
            base,
            directory.appendingPathComponent("\(name)-wal"),
            directory.appendingPathComponent("\(name)-shm")
        ]
    }

    private static func removeStoreFiles() {
        for url in sidecarURLs(for: storeURL) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves the store at `base` (and its sidecars) aside to `*.corrupt` so a failed
    /// migration doesn't destroy data outright; a later build could offer to recover from it.
    private static func backupCorruptStore(at base: URL) {
        let manager = FileManager.default
        for url in sidecarURLs(for: base) where manager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("corrupt")
            try? manager.removeItem(at: backup)
            try? manager.moveItem(at: url, to: backup)
        }
    }
}
