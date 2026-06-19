import Foundation
import Security

// `nonisolated` so this stateless Keychain wrapper can be constructed and used from any
// context (it's already `@unchecked Sendable`). Without it the project's default
// main-actor isolation makes `init` main-actor-only, which warns when it's used as a
// default argument in a nonisolated initializer. Used to persist OAuth tokens (Strava).
nonisolated final class KeychainTokenStore: @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func setToken(_ token: String?) {
        setData(token.map { Data($0.utf8) })
    }

    func token() -> String? {
        data().flatMap { String(data: $0, encoding: .utf8) }
    }

    func setData(_ data: Data?) {
        guard let data else {
            clear()
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func data() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    func setSession<T: Encodable>(_ value: T?) {
        guard let value else {
            clear()
            return
        }
        setData(try? JSONEncoder().encode(value))
    }

    func session<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = data() else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
