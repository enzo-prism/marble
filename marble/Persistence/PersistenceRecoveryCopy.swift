import Foundation
import CryptoKit

/// Export only while the database is unavailable and no container is registered.
/// Preserve the SQLite/WAL/SHM set together; never rename or remove any source.
nonisolated enum PersistenceRecoveryCopy {
    enum CopyError: Error { case noStore, sourceChanged, verificationFailed }

    @concurrent
    static func prepare(at store: URL) async throws -> URL {
        try prepareCopy(at: store)
    }

    static func prepareCopy(
        at store: URL,
        destinationDirectory: URL? = nil,
        copyFile: ((URL, URL) throws -> Void)? = nil
    ) throws -> URL {
        let manager = FileManager.default
        let root = destinationDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("RecoveryCopies", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "Marble-Recovery-\(UUID().uuidString)"
        let staging = root.appendingPathComponent(name + ".partial", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        let files = [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
            .filter { manager.fileExists(atPath: $0.path) }
        guard files.contains(store) else { throw CopyError.noStore }
        var fingerprints: [URL: SHA256.Digest] = [:]
        for source in files {
            let fingerprint = try digest(source)
            let copy = staging.appendingPathComponent(source.lastPathComponent)
            if let copyFile { try copyFile(source, copy) }
            else { try manager.copyItem(at: source, to: copy) }
            let handle = try FileHandle(forWritingTo: copy)
            try handle.synchronize()
            try handle.close()
            guard try digest(copy) == fingerprint else { throw CopyError.verificationFailed }
            fingerprints[source] = fingerprint
        }
        // A failed open can still have touched WAL state. Reject the export if the
        // source set changed during copying; keep both source and partial evidence.
        let currentFiles = [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
            .filter { manager.fileExists(atPath: $0.path) }
        guard currentFiles == files else { throw CopyError.sourceChanged }
        for source in files {
            guard try digest(source) == fingerprints[source] else { throw CopyError.sourceChanged }
        }
        let completed = root.appendingPathComponent(name, isDirectory: true)
        try manager.moveItem(at: staging, to: completed)
        // Foundation produces a zip for a coordinated upload of a directory. Copy
        // its temporary URL before leaving the accessor, keeping the verified set.
        let archive = root.appendingPathComponent(name + ".zip")
        var coordinationError: NSError?
        var archiveError: Error?
        NSFileCoordinator().coordinate(readingItemAt: completed, options: .forUploading, error: &coordinationError) { zipped in
            do { try manager.copyItem(at: zipped, to: archive) }
            catch { archiveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let archiveError { throw archiveError }
        _ = try digest(archive)
        return archive
    }

    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize()
    }
}
