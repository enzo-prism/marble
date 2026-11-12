import CryptoKit
import Foundation
import Security

/// A bounded handoff queue, separate from widget state and editable app drafts.
/// Text stays on this device and is readable only while it is unlocked.
nonisolated enum SharedWorkoutInbox {
    struct Item: Codable, Identifiable, Sendable, Equatable {
        let id: UUID
        let createdAt: Date
        let text: String
    }
    enum InboxError: LocalizedError, Equatable {
        case empty, tooLarge, full, unavailable
        var errorDescription: String? {
            switch self {
            case .empty: "No workout text was found. Share text or a text/CSV file."
            case .tooLarge: "This workout is too large. Share up to 64 KB of text."
            case .full: "Your Marble inbox is full. Review or delete a saved workout before sharing another."
            case .unavailable: "Marble couldn't save this workout. Unlock your iPhone and try again."
            }
        }
    }
    static let maximumBytes = 65_536
    static let maximumItems = 5
    /// Host retries of the same share are collapsed only inside this window.
    static let retryWindow: TimeInterval = 600
    static func isWithinRetryWindow(_ createdAt: Date, relativeTo now: Date) -> Bool {
        abs(createdAt.timeIntervalSince(now)) < retryWindow
    }
    private static let service = "marble.sharedWorkoutInbox"
    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccessGroup as String: SharedKeychain.accessGroup]
    }

    private struct Record {
        let item: Item
        let persistentReference: Data
    }
    private static func records() throws -> [Record] {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecReturnPersistentRef as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let values = result as? [[String: Any]] else { throw InboxError.unavailable }
        return try values.map { value in
            guard let data = value[kSecValueData as String] as? Data,
                  let reference = value[kSecValuePersistentRef as String] as? Data else { throw InboxError.unavailable }
            return Record(item: try JSONDecoder().decode(Item.self, from: data), persistentReference: reference)
        }
    }
    static func items() throws -> [Item] {
        try records().map(\.item).sorted { $0.createdAt < $1.createdAt }
    }

    /// Identity for an item still sitting in the inbox. A host retry of the
    /// same share within `retryWindow` reuses that row. The key is SHA-256 of
    /// trim-only text: leading and trailing whitespace are ignored, interior
    /// whitespace and case are significant.
    static func dedupeKey(for text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum PreparedSave: Equatable {
        case reuse(Item)
        case insert(Item)
    }

    static func prepareSave(
        text: String,
        existing: [Item],
        id: UUID = UUID(),
        createdAt: Date? = nil,
        now: Date = Date()
    ) throws -> PreparedSave {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw InboxError.empty }
        guard cleaned.utf8.count <= maximumBytes else { throw InboxError.tooLarge }
        let key = dedupeKey(for: cleaned)
        let timestamp = createdAt ?? now
        if let match = existing.first(where: {
            dedupeKey(for: $0.text) == key && isWithinRetryWindow($0.createdAt, relativeTo: now)
        }) {
            return .reuse(match)
        }
        guard existing.count < maximumItems else { throw InboxError.full }
        return .insert(Item(id: id, createdAt: timestamp, text: cleaned))
    }

    /// After a write, keep the earliest in-window row with this hash and drop
    /// later duplicates from a double Post.
    static func reconcile(inserted: Item, among items: [Item], now: Date) -> (keeper: Item, extras: [Item]) {
        let key = dedupeKey(for: inserted.text)
        let matches = items.filter {
            dedupeKey(for: $0.text) == key && isWithinRetryWindow($0.createdAt, relativeTo: now)
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let keeper = matches.first ?? inserted
        let extras = matches.filter { $0.id != keeper.id }
        return (keeper, extras)
    }

    /// Share extensions must complete after a successful write. Failures show
    /// an error, then cancel when the user acknowledges it.
    enum SharePosting {
        enum Disposition {
            case completeRequest
            case presentErrorThenCancel(Error)
        }

        static func disposition(saving: () throws -> Void) -> Disposition {
            do {
                try saving()
                return .completeRequest
            } catch {
                return .presentErrorThenCancel(error)
            }
        }

        final class CompletionGuard: @unchecked Sendable {
            private var finished = false
            func completeIfNeeded(_ work: () -> Void) -> Bool {
                guard !finished else { return false }
                finished = true
                work()
                return true
            }
        }

        static func performPost(
            saving: () throws -> Void,
            complete: () -> Void,
            presentError: (String, @escaping () -> Void) -> Void,
            cancel: @escaping (Error) -> Void,
            completion: CompletionGuard
        ) {
            switch disposition(saving: saving) {
            case .completeRequest:
                _ = completion.completeIfNeeded(complete)
            case .presentErrorThenCancel(let error):
                presentError(error.localizedDescription, {
                    _ = completion.completeIfNeeded { cancel(error) }
                })
            }
        }
    }

    nonisolated protocol Storage {
        func load() throws -> [Item]
        func insert(_ item: Item) throws
        func delete(id: UUID) throws
    }

    struct KeychainStore: Storage {
        func load() throws -> [Item] { try SharedWorkoutInbox.items() }
        func insert(_ item: Item) throws {
            let data = try JSONEncoder().encode(item)
            // Five add-only slots make the capacity atomic across extension processes.
            // A slot is never updated or overwritten, even when two hosts share at once.
            for slot in 0..<maximumItems {
                var query = baseQuery
                query[kSecAttrAccount as String] = "slot-\(slot)"
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                query[kSecValueData as String] = data
                let status = SecItemAdd(query as CFDictionary, nil)
                if status == errSecSuccess { return }
                if status != errSecDuplicateItem { throw InboxError.unavailable }
            }
            throw InboxError.full
        }
        func delete(id: UUID) throws { try SharedWorkoutInbox.remove(id: id) }
    }

    final class MemoryStore: Storage, @unchecked Sendable {
        nonisolated(unsafe) var items: [Item] = []
        nonisolated func load() throws -> [Item] { items }
        nonisolated func insert(_ item: Item) throws { items.append(item) }
        nonisolated func delete(id: UUID) throws { items.removeAll { $0.id == id } }
    }

    @discardableResult
    static func save(text: String, now: Date = Date(), using storage: any Storage = KeychainStore()) throws -> Item {
        switch try prepareSave(text: text, existing: try storage.load(), createdAt: now, now: now) {
        case .reuse(let item):
            return item
        case .insert(let item):
            try storage.insert(item)
            let (keeper, extras) = reconcile(inserted: item, among: try storage.load(), now: now)
            for extra in extras { try storage.delete(id: extra.id) }
            return keeper
        }
    }

    static func remove(id: UUID) throws {
        guard let record = try records().first(where: { $0.item.id == id }) else { return }
        var query = baseQuery
        // Persistent references identify this exact row. A stale review cannot
        // delete a different workout that subsequently reused the same slot.
        query[kSecValuePersistentRef as String] = record.persistentReference
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw InboxError.unavailable }
    }
}
