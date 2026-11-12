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

    /// Content-addressed identity so a host retry of the same share cannot
    /// enqueue a second inbox item.
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
        createdAt: Date = Date()
    ) throws -> PreparedSave {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw InboxError.empty }
        guard cleaned.utf8.count <= maximumBytes else { throw InboxError.tooLarge }
        let key = dedupeKey(for: cleaned)
        if let match = existing.first(where: { dedupeKey(for: $0.text) == key }) {
            return .reuse(match)
        }
        guard existing.count < maximumItems else { throw InboxError.full }
        return .insert(Item(id: id, createdAt: createdAt, text: cleaned))
    }

    /// Share extensions must complete or cancel immediately after the write.
    enum SharePosting {
        enum Disposition {
            case completeRequest
            case cancelRequest(Error)
        }

        static func disposition(saving: () throws -> Void) -> Disposition {
            do {
                try saving()
                return .completeRequest
            } catch {
                return .cancelRequest(error)
            }
        }
    }

    @discardableResult
    static func save(text: String) throws -> Item {
        switch try prepareSave(text: text, existing: try items()) {
        case .reuse(let item):
            return item
        case .insert(let item):
            let data = try JSONEncoder().encode(item)
            // Five add-only slots make the capacity atomic across extension processes.
            // A slot is never updated or overwritten, even when two hosts share at once.
            for slot in 0..<maximumItems {
                var query = baseQuery
                query[kSecAttrAccount as String] = "slot-\(slot)"
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                query[kSecValueData as String] = data
                let status = SecItemAdd(query as CFDictionary, nil)
                if status == errSecSuccess { return item }
                if status != errSecDuplicateItem { throw InboxError.unavailable }
            }
            throw InboxError.full
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
