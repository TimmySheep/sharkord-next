import Foundation
import Security

/// Stores the JWT in the login keychain, keyed by server origin, so the client can
/// auto login. The token is a credential: it never goes to UserDefaults or a file.
public struct KeychainTokenStore: Sendable {
    private let service: String

    public init(service: String = "com.timmysheep.sharkord.macos") {
        self.service = service
    }

    public func token(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func setToken(_ token: String, for account: String) -> Bool {
        let data = Data(token.utf8)
        deleteToken(for: account)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func deleteToken(for account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)

        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

