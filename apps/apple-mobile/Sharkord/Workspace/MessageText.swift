import Foundation

/// Message HTML is produced by the server's sanitiser (paragraphs, hard breaks, mentions,
/// emoji images). The first version shows it as plain text, so this strips the markup in
/// one place instead of each row doing its own dance.
enum MessageText {
    static func plainText(fromHTML html: String?) -> String {
        guard let html, !html.isEmpty else {
            return ""
        }

        var text = html
        text = replacingOccurrences(of: "<br[^>]*>", in: text, with: "\n")
        text = replacingOccurrences(of: "</p>\\s*<p[^>]*>", in: text, with: "\n")
        text = replacingOccurrences(of: "</p>", in: text, with: "\n")
        text = replacingOccurrences(of: "<p[^>]*>", in: text, with: "")
        text = replacingOccurrences(of: "<img[^>]*alt=\"([^\"]*)\"[^>]*>", in: text, with: "$1")
        text = replacingOccurrences(of: "<[^>]+>", in: text, with: "")

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]

        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Server timestamps are milliseconds since the epoch.
    static func date(fromMilliseconds value: Int) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1000)
    }

    private static func replacingOccurrences(
        of pattern: String,
        in text: String,
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
