import Foundation
import Security

struct WatchLoginCredentials: Codable {
    let server: String
    let identity: String
    let password: String
    let serverPassword: String
}

struct WatchCredentialStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.timmysheep.cove.watch"
    private let account = "saved-login"

    func load() throws -> WatchLoginCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }

        do {
            return try JSONDecoder().decode(WatchLoginCredentials.self, from: data)
        } catch {
            try? remove()
            throw error
        }
    }

    func save(_ credentials: WatchLoginCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            updates.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw keychainError(updateStatus)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}
