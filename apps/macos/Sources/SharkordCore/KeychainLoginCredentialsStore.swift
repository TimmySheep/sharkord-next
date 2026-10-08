import Foundation
import Security

public struct StoredLoginCredentials: Codable, Equatable, Sendable {
    public let host: String
    public let identity: String
    public let password: String
    public let serverPassword: String?

    public init(host: String, identity: String, password: String, serverPassword: String?) {
        self.host = host
        self.identity = identity
        self.password = password
        self.serverPassword = serverPassword
    }
}

/// keeps the last successful login in the user's keychain instead of app preferences.
public struct KeychainLoginCredentialsStore: Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.timmysheep.cove.login",
        account: String = "last-login"
    ) {
        self.service = service
        self.account = account
    }

    public func credentials() -> StoredLoginCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let credentials = try? JSONDecoder().decode(StoredLoginCredentials.self, from: data)
        else {
            return nil
        }

        return credentials
    }

    @discardableResult
    public func setCredentials(_ credentials: StoredLoginCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else {
            return false
        }

        let query = baseQuery
        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, update)

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func deleteCredentials() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
