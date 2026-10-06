import Foundation

/// localization for the macOS client. the resource tree under Resources/locales is
/// copied verbatim from the web client's i18next locales, so lookup follows i18next
/// semantics: dotted keys address nested objects and `key_one` / `key_other` are the
/// plural variants selected by a `count` argument.
public enum L10n {
    public static let supportedLanguages: [(code: String, nativeName: String)] = [
        (code: "en", nativeName: "English"),
        (code: "cs", nativeName: "Čeština"),
        (code: "es", nativeName: "Español"),
        (code: "fr", nativeName: "Français"),
        (code: "it", nativeName: "Italiano"),
        (code: "ru", nativeName: "Русский"),
        (code: "zh", nativeName: "中文"),
        (code: "pt-BR", nativeName: "Português")
    ]

    public enum DateStyle {
        case short
        case medium
        case long
        case time
        case dateTime
    }

    private static let languageDefaultsKey = "sharkord.language"

    // the persisted choice wins over detection so a user who picked a language keeps it
    // even when the system locale changes underneath the app
    public static var language: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: languageDefaultsKey), isSupported(saved) {
                return saved
            }
            return detectedLanguage
        }
        set {
            // an unsupported code would only produce missing-file lookups, so it is ignored
            guard isSupported(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: languageDefaultsKey)
        }
    }

    /// looks up `key` in `<ns>.json`, first for the current language and then for english.
    /// returns the key itself when neither has it, which is what i18next shows too, so a
    /// missing translation is visible instead of silently rendering as empty text.
    public static func t(
        _ key: String,
        ns: String = "common",
        _ args: [String: CustomStringConvertible] = [:]
    ) -> String {
        let candidates = lookupCandidates(for: key, args: args)
        for lang in [language, "en"] {
            let strings = strings(language: lang, ns: ns)
            for candidate in candidates {
                if let template = strings[candidate] {
                    return interpolate(template, args)
                }
            }
        }
        return key
    }

    public static func date(_ date: Date, style: DateStyle = .short) -> String {
        dateFormatter(style: style).string(from: date)
    }

    public static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - lookup internals

    private static func isSupported(_ code: String) -> Bool {
        supportedLanguages.contains { $0.code == code }
    }

    // matches the web client's detection: exact code first so "pt-BR" is reachable at all,
    // then the two-letter prefix, then english
    private static let detectedLanguage: String = {
        for preferred in Locale.preferredLanguages {
            if supportedLanguages.contains(where: { $0.code == preferred }) {
                return preferred
            }
            let twoLetter = preferred.split(separator: "-").first.map(String.init) ?? preferred
            if supportedLanguages.contains(where: { $0.code == twoLetter }) {
                return twoLetter
            }
        }
        return "en"
    }()

    // i18next resolves the plural variant before the base key, and the base key before
    // falling back to english
    private static func lookupCandidates(for key: String, args: [String: CustomStringConvertible]) -> [String] {
        guard let count = args["count"].flatMap({ Int(String(describing: $0)) }) else {
            return [key]
        }
        return [count == 1 ? "\(key)_one" : "\(key)_other", key]
    }

    private static func interpolate(_ template: String, _ args: [String: CustomStringConvertible]) -> String {
        guard template.contains("{{") else { return template }
        var result = ""
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "}}") else {
                result += "{{" + rest
                return result
            }
            let name = rest[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let value = args[name] {
                result += String(describing: value)
            } else {
                // an unknown placeholder is left untouched so the mismatch stays visible
                result += "{{" + rest[..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    // MARK: - resources

    // parsed once per language + namespace pair. the json trees hold hundreds of keys per
    // namespace and t() can run for every visible row of a message list
    private static var stringsCache: [String: [String: String]] = [:]

    private static func strings(language: String, ns: String) -> [String: String] {
        let cacheKey = "\(language)/\(ns)"
        if let cached = stringsCache[cacheKey] {
            return cached
        }
        var loaded: [String: String] = [:]
        if let url = Bundle.module.url(forResource: ns, withExtension: "json", subdirectory: "locales/\(language)"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            flatten(json, prefix: "", into: &loaded)
        }
        stringsCache[cacheKey] = loaded
        return loaded
    }

    // permissions.json and connect.json group keys in nested objects, i18next addresses
    // those with dots ("server.MANAGE_ROLES"), so the tree is flattened to dotted keys
    private static func flatten(_ object: [String: Any], prefix: String, into result: inout [String: String]) {
        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let string = value as? String {
                result[path] = string
            } else if let nested = value as? [String: Any] {
                flatten(nested, prefix: path, into: &result)
            }
        }
    }

    // MARK: - dates

    private static let localeIdentifiers: [String: String] = [
        "en": "en_US",
        "cs": "cs_CZ",
        "es": "es_ES",
        "fr": "fr_FR",
        "it": "it_IT",
        "ru": "ru_RU",
        "zh": "zh_CN",
        "pt-BR": "pt_BR"
    ]

    private static var currentLocale: Locale {
        Locale(identifier: localeIdentifiers[language] ?? "en_US")
    }

    // DateFormatter creation is expensive and chat screens format one per visible message
    private static var formatterCache: [String: DateFormatter] = [:]
    private static var relativeFormatterCache: [String: RelativeDateTimeFormatter] = [:]

    private static func dateFormatter(style: DateStyle) -> DateFormatter {
        let cacheKey = "\(language)/\(style)"
        if let cached = formatterCache[cacheKey] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        switch style {
        case .short:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        case .medium:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .long:
            formatter.dateStyle = .long
            formatter.timeStyle = .none
        case .time:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .dateTime:
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        formatterCache[cacheKey] = formatter
        return formatter
    }

    private static var relativeFormatter: RelativeDateTimeFormatter {
        if let cached = relativeFormatterCache[language] {
            return cached
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = currentLocale
        formatter.unitsStyle = .full
        relativeFormatterCache[language] = formatter
        return formatter
    }
}
