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

public enum MessageHTML {
    /// Turns a plain text composer value into the HTML the server expects. The rich web
    /// editor sends HTML; a native plain-text field only has to escape and keep the line
    /// structure, which `sanitizeMessageHtml` allows as `<p>` and `<br class="hard-break">`.
    public static func fromPlainText(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")

        return lines
            .map { line in
                "<p>\(escape(line))</p>"
            }
            .joined(separator: "<br class=\"hard-break\">")
    }

    /// Strips the tags a message can carry so the list can show plain text.
    public static func toPlainText(_ html: String) -> String {
        var output = html
        output = output.replacingOccurrences(of: "<br class=\"hard-break\">", with: "\n")
        output = output.replacingOccurrences(of: "<br>", with: "\n")
        output = output.replacingOccurrences(of: "</p><p>", with: "\n")
        output = output.replacingOccurrences(of: "<p>", with: "")
        output = output.replacingOccurrences(of: "</p>", with: "")
        output = output.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        return decodeEntities(output)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
