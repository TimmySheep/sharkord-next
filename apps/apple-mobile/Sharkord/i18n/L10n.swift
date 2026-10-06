import Foundation

/// Runtime-selectable localisation. The tables live in `Resources/<lang>.lproj/
/// Localizable.strings` and are loaded per language, so switching language inside the app
/// takes effect immediately instead of waiting for a relaunch. Supported this version:
/// English, Simplified Chinese, Spanish, French, German.
enum L10n {
    static let supportedLanguages: [(code: String, nativeName: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch")
    ]

    static let defaultLanguage = "en"
    private static let storageKey = "app.language"

    /// Selected language, persisted across launches.
    static var current: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? defaultLanguage }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    private static var tables: [String: [String: String]] = [:]

    static func t(_ key: String) -> String {
        if let value = table(for: current)?[key] {
            return value
        }
        if let value = table(for: defaultLanguage)?[key] {
            return value
        }
        return key
    }

    /// Formats a translated string: `String(format:)` with the current locale.
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    private static func table(for language: String) -> [String: String]? {
        if let cached = tables[language] {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language
        ), let data = try? Data(contentsOf: url) else {
            return nil
        }

        guard let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let table = parsed as? [String: String] else {
            return nil
        }

        tables[language] = table
        return table
    }
}
