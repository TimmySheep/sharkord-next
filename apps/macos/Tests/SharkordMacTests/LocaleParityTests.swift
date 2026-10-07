import XCTest
@testable import SharkordMac

/// Guards the two ways localization can drift silently: a translation goes missing in one
/// of the eight languages, or the app references a key that no locale file defines.
///
/// The web client's namespaces are a verbatim copy and are allowed to have gaps, because
/// `L10n` falls back to English for them. The `macos` namespace is ours, so it is held to
/// full parity.
final class LocaleParityTests: XCTestCase {
    private let localesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/locales")

    private let sourcesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SharkordMac")

    private func json(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func flattened(_ object: [String: Any], prefix: String = "") -> Set<String> {
        var keys: Set<String> = []

        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"

            if let nested = value as? [String: Any] {
                keys.formUnion(flattened(nested, prefix: path))
            } else {
                keys.insert(path)
            }
        }

        return keys
    }

    private func stringValues(_ object: [String: Any], prefix: String = "") -> [String: String] {
        var values: [String: String] = [:]

        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"

            if let nested = value as? [String: Any] {
                values.merge(stringValues(nested, prefix: path)) { _, new in new }
            } else if let string = value as? String {
                values[path] = string
            }
        }

        return values
    }

    func testEveryLanguageHasEveryNamespace() throws {
        let languages = L10n.supportedLanguages.map(\.code)
        let expected = try XCTUnwrap(namespaces(in: "en"))

        for language in languages {
            let found = try XCTUnwrap(namespaces(in: language), "no locale directory for \(language)")
            XCTAssertEqual(found, expected, "namespace files differ for \(language)")
        }
    }

    func testEveryLocaleFileParses() throws {
        for language in L10n.supportedLanguages.map(\.code) {
            for namespace in try XCTUnwrap(namespaces(in: language)) {
                let url = localesURL.appendingPathComponent(language).appendingPathComponent(namespace)
                _ = try json(at: url)
            }

            let connect = try json(at: localesURL.appendingPathComponent("\(language)/connect.json"))
            let optional = try XCTUnwrap(connect["optional"] as? String)
            XCTAssertFalse(optional.isEmpty, "\(language).connect.optional is empty")
            XCTAssertNotEqual(optional, "optional", "\(language).connect.optional is missing")
        }
    }

    func testMacosNamespaceHasIdenticalKeysInEveryLanguage() throws {
        let english = flattened(try json(at: localesURL.appendingPathComponent("en/macos.json")))
        XCTAssertFalse(english.isEmpty)

        for language in L10n.supportedLanguages.map(\.code) {
            let keys = flattened(try json(at: localesURL.appendingPathComponent("\(language)/macos.json")))
            XCTAssertEqual(keys, english, "macos.json keys differ for \(language)")
        }
    }

    func testMacosNamespaceIsTranslatedNotStubbed() throws {
        for language in L10n.supportedLanguages.map(\.code) {
            let values = stringValues(try json(at: localesURL.appendingPathComponent("\(language)/macos.json")))

            for (key, value) in values {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language).macos.\(key) is empty")
                XCTAssertNotEqual(value, key, "\(language).macos.\(key) was never translated")
            }
        }
    }

    /// Walks the UI for `L10n.t("key", ns: "namespace")` call sites and checks each one
    /// resolves in English. Keys built with string interpolation are skipped, they cannot
    /// be checked statically.
    func testEveryKeyUsedByTheUIExists() throws {
        let pattern = try NSRegularExpression(pattern: #"L10n\.t\(\s*"([^"\\]+)"\s*,\s*ns:\s*"([^"\\]+)""#)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil)
        )

        // one entry per namespace, resolved once: the scan reads the same handful of files
        // over and over otherwise
        var roots: [String: Set<String>] = [:]
        var checked = 0

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)

            for match in pattern.matches(in: contents, range: range) {
                let key = (contents as NSString).substring(with: match.range(at: 1))
                let namespace = (contents as NSString).substring(with: match.range(at: 2))

                if roots[namespace] == nil {
                    let file = localesURL.appendingPathComponent("en/\(namespace).json")
                    XCTAssertNoThrow(
                        try json(at: file),
                        "\(url.lastPathComponent) references namespace \(namespace), which does not exist"
                    )
                    roots[namespace] = (try? flattened(json(at: file))) ?? []
                }

                XCTAssertTrue(
                    roots[namespace]?.contains(key) == true,
                    "\(url.lastPathComponent) references missing key \(namespace).\(key)"
                )
                checked += 1
            }
        }

        XCTAssertGreaterThan(checked, 100, "the scan did not find the expected call sites")
    }

    private func namespaces(in language: String) throws -> [String]? {
        let directory = localesURL.appendingPathComponent(language)

        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }

        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }
}
