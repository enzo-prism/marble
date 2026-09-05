import Foundation
import SwiftData

enum PersistenceController {
    /// Explicitly ephemeral containers are for previews and deterministic tests only.
    /// Production callers must use `openContainer`, which never hides a disk failure.
    static func makeContainer(useInMemory: Bool) -> ModelContainer {
        precondition(useInMemory, "Use openContainer() for persistent storage")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, migrationPlan: MarbleMigrationPlan.self, configurations: [configuration])
        } catch {
            fatalError("Failed to create test ModelContainer: \(error)")
        }
    }

    static func openContainer(useInMemory: Bool = false) throws -> ModelContainer {
        if useInMemory { return makeContainer(useInMemory: true) }
        if TestHooks.resetDatabase { removeStoreFiles() }
        return try makeRecoveringContainer(at: storeURL)
    }

    /// A failed open never renames a live SQLite file, separates its WAL, creates a
    /// replacement database, or permits volatile logging. Keep all source files in
    /// place for a later retry, OS unlock, migration fix, or supported recovery.
    static func makeRecoveringContainer(
        at url: URL,
        opener: ((URL) throws -> ModelContainer)? = nil
    ) throws -> ModelContainer {
        do {
            return try (opener ?? makePersistentContainer)(url)
        } catch {
            throw PersistenceOpenFailure.classify(error)
        }
    }

    private static var schema: Schema { Schema(versionedSchema: MarbleSchemaV6.self) }

    private static func makePersistentContainer(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: MarbleMigrationPlan.self, configurations: [configuration])
    }

    static var storeURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Marble", isDirectory: true)
            .appendingPathComponent("Marble.store")
    }

    static func sidecarURLs(for base: URL) -> [URL] {
        [base, URL(fileURLWithPath: base.path + "-wal"), URL(fileURLWithPath: base.path + "-shm")]
    }

    private static func removeStoreFiles() {
        for url in sidecarURLs(for: storeURL) { try? FileManager.default.removeItem(at: url) }
    }
}

/// Classify structured error codes, never localized descriptions. Unknown/migration
/// failures are not proof of corruption and must not trigger destructive recovery.
nonisolated enum PersistenceOpenFailure: String, Error, LocalizedError, Sendable {
    case temporarilyUnavailable, damagedStore, incompatibleStore, unknown

    var errorDescription: String? { "Marble couldn't open your saved workouts. Open Marble to retry." }

    var guidance: String {
        switch self {
        case .temporarilyUnavailable:
            "Your workout storage is temporarily unavailable. Unlock your iPhone, check that storage is available, then try again."
        case .damagedStore:
            "Your workout database needs recovery. Keep Marble installed to preserve your files. A recovery copy can help with support."
        case .incompatibleStore:
            "Your workout database couldn't be opened by this version of Marble. Check for an app update, then try again."
        case .unknown:
            "Marble couldn't open your workout database. Try again, or keep a recovery copy for support."
        }
    }

    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        var pending = [error as NSError]
        var visited = Set<ObjectIdentifier>()
        var result: Self = .unknown
        while let current = pending.popLast(), visited.count < 32 {
            guard visited.insert(ObjectIdentifier(current)).inserted else { continue }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
            if let detailed = current.userInfo["NSDetailedErrors"] as? [NSError] { pending.append(contentsOf: detailed) }
            if current.domain == NSPOSIXErrorDomain && [1, 5, 11, 13, 16, 28, 30].contains(current.code) { return .temporarilyUnavailable }
            if current.domain == NSCocoaErrorDomain && [257, 513, 640, 642].contains(current.code) { return .temporarilyUnavailable }
            if current.domain == "NSSQLiteErrorDomain" {
                let primaryCode = current.code & 0xff
                if [3, 5, 6, 8, 10, 13, 14, 23].contains(primaryCode) { return .temporarilyUnavailable }
                if [11, 26].contains(primaryCode) { result = .damagedStore }
            }
            if current.domain == NSCocoaErrorDomain && (134100...134199).contains(current.code), result == .unknown { result = .incompatibleStore }
        }
        return result
    }
}
