import Foundation

/// The message content vocabulary. The server stores messages as HTML produced by the web
/// client's editor and normalised by `sanitizeMessageHtml`, so a native client has to speak
/// exactly that vocabulary to be interchangeable with the web client:
///
/// - blocks: `<p>` and `<pre>` (headings and list items are rewritten to `<p>` on save)
/// - line breaks: `<br class="hard-break">`
/// - inline: `<strong>`, `<em>`, `<code>`, `<a href target rel>`
/// - mentions: `<span class="mention" data-user-id="N" data-name="Name">…</span>`
/// - channel refs: `<span class="channel-reference" data-channel-id="N" data-name="Name">…</span>`
/// - custom emoji: `<img class="emoji-image" src="/public/..." alt=":name:">`, sometimes
///   wrapped in `<span data-type="emoji" data-name="name">`
/// - commands: `<span class="plugin-command">…</span>`
///
/// Image sources are restricted to this server's `/public` path or `cdn.jsdelivr.net`, which
/// is where the bundled GitHub emoji set is served from.
public enum MessageHTML {
    // MARK: - outgoing

    /// Turns a plain text composer value into the HTML the server expects. The web editor
    /// wraps every hard break inside one block: `<p>a<br class="hard-break">b</p>`.
    public static func fromPlainText(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map(escape)

        return "<p>\(lines.joined(separator: "<br class=\"hard-break\">"))</p>"
    }

    /// A trailing hard break before a closing block tag is invisible in static rendering, so
    /// the web client rewrites it to an empty `<p></p>`. Mirrors `normalizeLineBreaks`.
    public static func normalizeLineBreaks(_ html: String) -> String {
        let pattern = "<br\\s[^>]*class=\"hard-break\"[^>]*>\\s*</(p|pre)>(\\s*<(?:p|pre))"

        return html.replacingOccurrences(
            of: pattern,
            with: "</$1><p></p>$2",
            options: .regularExpression
        )
    }

    /// Wraps explicit http/https URLs in anchors, the way the web client's `linkifyHtml`
    /// does before sending. Matches `linkify-it`'s http behaviour closely enough for chat
    /// text: scheme, host, optional port, path and query, no trailing punctuation.
    public static func linkify(_ html: String) -> String {
        let parts = splitOutsideTags(html)

        return parts
            .map { part -> String in
                if part.range(of: "^<a\\b", options: .regularExpression) != nil {
                    return normalizeAnchorHref(part)
                }

                if part.hasPrefix("<") {
                    return part
                }

                return linkifyText(part)
            }
            .joined()
    }

    /// An anchor whose visible text is a bare url points at that url, not at whatever the
    /// editor happened to put in `href`. Mirrors `normalizeAnchorHref`.
    private static func normalizeAnchorHref(_ anchorHtml: String) -> String {
        guard
            let href = attributeValue(named: "href", in: anchorHtml),
            let inner = innerText(ofAnchor: anchorHtml)
        else {
            return anchorHtml
        }

        let label = inner.trimmingCharacters(in: .whitespaces)

        guard
            isExplicitHTTPURL(label),
            label.range(of: "<") == nil,
            href != label
        else {
            return anchorHtml
        }

        return anchorHtml.replacingOccurrences(
            of: "href=\"\(href)\"",
            with: "href=\"\(escapeAttribute(label))\""
        )
    }

    private static func isExplicitHTTPURL(_ value: String) -> Bool {
        value.range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func attributeValue(named name: String, in html: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)

        guard let match = regex.firstMatch(in: html, range: range) else {
            return nil
        }

        for group in 2...3 {
            if let valueRange = Range(match.range(at: group), in: html) {
                return String(html[valueRange])
            }
        }

        return nil
    }

    private static func innerText(ofAnchor anchorHtml: String) -> String? {
        guard
            let openEnd = anchorHtml.range(of: ">")?.upperBound,
            let closeStart = anchorHtml.range(of: "</a>", options: .regularExpression)?.lowerBound,
            openEnd <= closeStart
        else {
            return nil
        }

        return String(anchorHtml[openEnd..<closeStart])
    }

    /// All pre-send transformations, in the same order the web client applies them.
    public static func prepare(_ html: String) -> String {
        linkify(normalizeLineBreaks(html))
    }

    public static func mention(userId: Int, name: String) -> String {
        "<span class=\"mention\" data-user-id=\"\(userId)\" data-name=\"\(escapeAttribute(name))\">\(escape("@\(name)"))</span>"
    }

    public static func channelReference(channelId: Int, name: String) -> String {
        "<span class=\"channel-reference\" data-channel-id=\"\(channelId)\" data-name=\"\(escapeAttribute(name))\">\(escape("#\(name)"))</span>"
    }

    /// A custom emoji inserted inline. `src` is a server path such as `/public/emoji/12`.
    public static func emoji(name: String, src: String) -> String {
        "<img class=\"emoji-image\" src=\"\(escapeAttribute(src))\" alt=\":\(escapeAttribute(name)):\">"
    }

    public static func link(href: String, label: String) -> String {
        "<a href=\"\(escapeAttribute(href))\" target=\"_blank\" rel=\"noopener noreferrer\">\(escape(label))</a>"
    }

    /// Wraps `@Name` and `#Channel` tokens that match a known entity in their semantic spans,
    /// the way the editor's mention and channel reference nodes do. Longest names win so
    /// `@Ada Lovelace` is one mention rather than `@Ada` plus loose text.
    public static func withEntities(
        _ html: String,
        users: [(id: Int, name: String)],
        channels: [(id: Int, name: String)]
    ) -> String {
        var output = html

        for user in users.sorted(by: { $0.name.count > $1.name.count }) {
            let needle = "@\(escape(user.name))"
            output = output.replacingOccurrences(
                of: needle,
                with: mention(userId: user.id, name: user.name)
            )
        }

        for channel in channels.sorted(by: { $0.name.count > $1.name.count }) {
            let needle = "#\(escape(channel.name))"
            output = output.replacingOccurrences(
                of: needle,
                with: channelReference(channelId: channel.id, name: channel.name)
            )
        }

        return output
    }

    /// Turns `:name:` shortcodes into custom emoji elements, matching the web editor's
    /// emoji extension. Longest names win so `:party_parrot:` is not split.
    public static func withEmoji(_ html: String, emojis: [(name: String, src: String)]) -> String {
        var output = html

        for entry in emojis.sorted(by: { $0.name.count > $1.name.count }) {
            output = output.replacingOccurrences(
                of: ":\(escape(entry.name)):",
                with: emoji(name: entry.name, src: entry.src)
            )
        }

        return output
    }

    // MARK: - incoming

    /// Strips the tags a message can carry so lists and previews can show plain text. Keeps
    /// the web client's `getPlainTextFromHtml` behaviour: emoji, commands and channel
    /// references drop out entirely, mention labels stay.
    public static func toPlainText(_ html: String) -> String {
        let document = parse(html)
        var lines: [String] = []
        var current = ""

        for block in document.blocks {
            if !current.isEmpty {
                lines.append(current)
                current = ""
            }

            for span in block.spans {
                switch span.content {
                case .text(let value):
                    current += value
                case .lineBreak:
                    lines.append(current)
                    current = ""
                case .mention(_, let label):
                    current += label
                case .channelReference, .emoji, .media, .pluginCommand:
                    break
                }
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An empty message is one with no text, no media and no channel reference, matching the
    /// server's `isEmptyMessage`.
    public static func isEmpty(_ html: String?) -> Bool {
        guard let html, !html.isEmpty else {
            return true
        }

        if matches(html, pattern: "<(img|video|audio|iframe)\\b") {
            return false
        }

        if matches(html, pattern: "<span[^>]*(class=\"channel-reference\"|data-type=\"channel-reference\")") {
            return false
        }

        return toPlainText(html).isEmpty
    }

    /// Emoji-only messages render larger in the web client.
    public static func isEmojiOnly(_ html: String?) -> Bool {
        guard let html, !html.isEmpty else {
            return false
        }

        let document = parse(html)
        var sawEmoji = false

        for block in document.blocks {
            for span in block.spans {
                switch span.content {
                case .emoji:
                    sawEmoji = true
                case .lineBreak:
                    continue
                case .text(let value):
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return false
                    }
                case .mention, .channelReference, .media, .pluginCommand:
                    return false
                }
            }
        }

        return sawEmoji
    }

    // MARK: - parsing

    public static func parse(_ html: String) -> MessageDocument {
        var tokenizer = HTMLTokenizer(html)

        return MessageDocument(blocks: tokenizer.parse())
    }

    // MARK: - escaping

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ text: String) -> String {
        escape(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&lt;", with: "\u{0}")
        result = result.replacingOccurrences(of: "&gt;", with: "\u{1}")
        result = result.replacingOccurrences(of: "&quot;", with: "\u{2}")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "\u{0}", with: "<")
        result = result.replacingOccurrences(of: "\u{1}", with: ">")
        result = result.replacingOccurrences(of: "\u{2}", with: "\"")

        return decodeNumericEntities(result)
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        var output = text

        for match in regex.matches(in: text, range: range).reversed() {
            guard
                let full = Range(match.range, in: text),
                let radixFlag = Range(match.range(at: 1), in: text),
                let digits = Range(match.range(at: 2), in: text)
            else {
                continue
            }

            let radix = text[radixFlag].isEmpty ? 10 : 16
            let raw = String(text[digits])

            guard
                let scalarValue = UInt32(raw, radix: radix),
                let scalar = Unicode.Scalar(scalarValue)
            else {
                continue
            }

            output.replaceSubrange(full, with: String(Character(scalar)))
        }

        return output
    }

    /// Splits html into tag tokens and text runs, leaving tags and whole anchors (including
    /// their text) untouched so linkify does not nest anchors.
    private static func splitOutsideTags(_ html: String) -> [String] {
        var parts: [String] = []
        var rest = Substring(html)

        while let anchorStart = rest.range(of: "<a", options: .caseInsensitive) {
            let beforeAnchor = rest[rest.startIndex..<anchorStart.lowerBound]

            if !beforeAnchor.isEmpty {
                parts.append(contentsOf: splitPlain(String(beforeAnchor)))
            }

            guard let close = rest[anchorStart.lowerBound...].range(of: "</a>", options: .caseInsensitive) else {
                parts.append(String(rest[anchorStart.lowerBound...]))

                return parts
            }

            parts.append(String(rest[anchorStart.lowerBound..<close.upperBound]))
            rest = rest[close.upperBound...]
        }

        if !rest.isEmpty {
            parts.append(contentsOf: splitPlain(String(rest)))
        }

        return parts
    }

    private static func splitPlain(_ html: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var insideTag = false

        for character in html {
            if character == "<" {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }

                insideTag = true
                current.append(character)
            } else if character == ">" && insideTag {
                current.append(character)
                parts.append(current)
                current = ""
                insideTag = false
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func linkifyText(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: Self.urlPattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        var output = ""
        var cursor = text.startIndex

        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text), matchRange.lowerBound > cursor else {
                continue
            }

            let candidate = String(text[matchRange])
            let trimmed = trailingPunctuationTrimmed(candidate)

            guard let url = URL(string: trimmed), url.host != nil else {
                continue
            }

            output += text[cursor..<matchRange.lowerBound]
            output += link(href: trimmed, label: trimmed)

            cursor = text.index(matchRange.lowerBound, offsetBy: trimmed.count)
        }

        output += text[cursor...]

        return output
    }

    private static func trailingPunctuationTrimmed(_ value: String) -> String {
        var result = value

        while let last = result.last, ".,;:!?)]}'\"".contains(last) {
            // a closing paren is only trailing when the url has no matching opener
            if last == ")", result.filter({ $0 == "(" }).count >= result.filter({ $0 == ")" }).count {
                break
            }

            result.removeLast()
        }

        return result
    }

    private static let urlPattern = "(?:https?://)[^\\s<>\"']{2,}"
}

// MARK: - render model

public struct MessageDocument: Hashable, Sendable {
    public var blocks: [MessageBlock]

    public init(blocks: [MessageBlock]) {
        self.blocks = blocks
    }

    public var isEmpty: Bool {
        blocks.allSatisfy(\.isEmpty)
    }
}

public struct MessageBlock: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case paragraph
        case code
    }

    public var id: Int
    public var kind: Kind
    public var spans: [MessageSpan]

    public init(id: Int, kind: Kind, spans: [MessageSpan]) {
        self.id = id
        self.kind = kind
        self.spans = spans
    }

    public var isEmpty: Bool {
        spans.allSatisfy { span in
            if case .text(let value) = span.content {
                return value.isEmpty
            }

            return false
        }
    }
}

public struct MessageSpan: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case text(String)
        case lineBreak
        case mention(userId: Int?, label: String)
        case channelReference(channelId: Int?, label: String)
        case emoji(name: String, src: String?)
        case media(src: String, alt: String)
        case pluginCommand(String)
    }

    public var id: Int
    public var content: Content
    public var bold: Bool
    public var italic: Bool
    public var code: Bool
    public var href: String?

    public init(
        id: Int,
        content: Content,
        bold: Bool = false,
        italic: Bool = false,
        code: Bool = false,
        href: String? = nil
    ) {
        self.id = id
        self.content = content
        self.bold = bold
        self.italic = italic
        self.code = code
        self.href = href
    }
}

// MARK: - tokenizer

/// A small stack based html tokenizer for the message vocabulary. It is deliberately not a
/// general html parser: the server's sanitizer has already thrown away everything outside
/// the documented tag set before a message reaches a client.
struct HTMLTokenizer {
    private let source: String
    private var index: String.Index
    private var styles: [Tag] = []
    private var blocks: [MessageBlock] = []
    private var spans: [MessageSpan] = []
    private var kind: MessageBlock.Kind = .paragraph
    private var spanId = 0
    private var blockId = 0
    private var skipDepth = 0
    private var pending: PendingSpan?

    private struct PendingSpan {
        enum Kind {
            case mention(userId: Int?)
            case channelReference(channelId: Int?)
        }

        var kind: Kind
        var fallback: String
        var text = ""
    }

    init(_ html: String) {
        source = html
        index = html.startIndex
    }

    mutating func parse() -> [MessageBlock] {
        while index < source.endIndex {
            if source[index] == "<" {
                readTag()
            } else {
                readText()
            }
        }

        if pending != nil {
            closeSpan()
        }

        closeBlock()

        return blocks
    }

    // MARK: reading

    private mutating func readTag() {
        let start = index

        guard let end = source[index...].firstIndex(of: ">") else {
            index = source.endIndex

            return
        }

        let raw = String(source[source.index(after: start)..<end])
        index = source.index(after: end)

        applyTag(Tag(raw: raw))
    }

    private mutating func readText() {
        let start = index

        while index < source.endIndex, source[index] != "<" {
            index = source.index(after: index)
        }

        let raw = String(source[start..<index])
        let decoded = MessageHTML.decodeEntities(raw)

        if pending != nil {
            // the span's own text is the label the web client renders
            pending?.text += decoded

            return
        }

        guard skipDepth == 0, !decoded.isEmpty else {
            return
        }

        append(.text(decoded))
    }

    // MARK: tag handling

    private mutating func applyTag(_ tag: Tag) {
        switch tag.name {
        case "p":
            if tag.isClosing {
                closeBlock()
            } else {
                openBlock(.paragraph)
            }

        case "pre":
            if tag.isClosing {
                closeBlock()
            } else {
                openBlock(.code)
            }

        case "br":
            append(.lineBreak)

        case "strong", "b", "em", "i", "code", "a":
            if tag.isClosing {
                if let position = styles.lastIndex(where: { $0.name == tag.name }) {
                    styles.remove(at: position)
                }
            } else {
                styles.append(tag)
            }

        case "img":
            appendImage(tag)

        case "span":
            if tag.isClosing {
                closeSpan()
            } else {
                appendSpan(tag)
            }

        default:
            break
        }
    }

    private mutating func openBlock(_ kind: MessageBlock.Kind) {
        closeBlock()
        self.kind = kind
    }

    private mutating func closeBlock() {
        guard !spans.isEmpty || kind != .paragraph else {
            return
        }

        blocks.append(MessageBlock(id: blockId, kind: kind, spans: spans))
        blockId += 1
        spans = []
        kind = .paragraph
    }

    private mutating func append(_ content: MessageSpan.Content) {
        let flags = currentFlags

        if case .text(let value) = content,
           let last = spans.last,
           case .text(let previous) = last.content,
           last.bold == flags.bold,
           last.italic == flags.italic,
           last.code == flags.code,
           last.href == flags.href {
            spans[spans.count - 1] = MessageSpan(
                id: last.id,
                content: .text(previous + value),
                bold: flags.bold,
                italic: flags.italic,
                code: flags.code,
                href: flags.href
            )

            return
        }

        spans.append(
            MessageSpan(
                id: spanId,
                content: content,
                bold: flags.bold,
                italic: flags.italic,
                code: flags.code,
                href: flags.href
            )
        )
        spanId += 1
    }

    private mutating func appendImage(_ tag: Tag) {
        let src = tag.attribute("src") ?? ""

        guard !src.isEmpty else {
            return
        }

        if tag.classNames.contains("emoji-image") {
            let alt = tag.attribute("alt") ?? ""
            let name = alt.hasPrefix(":") && alt.hasSuffix(":")
                ? String(alt.dropFirst().dropLast())
                : alt

            append(.emoji(name: name, src: src))
        } else {
            append(.media(src: src, alt: tag.attribute("alt") ?? ""))
        }
    }

    private mutating func appendSpan(_ tag: Tag) {
        let classes = tag.classNames
        let type = tag.attribute("data-type")

        if classes.contains("mention") || type == "mention" || type == "user-mention" {
            pending = PendingSpan(
                kind: .mention(userId: tag.intAttribute("data-user-id")),
                fallback: tag.attribute("data-name").map { "@\($0)" } ?? ""
            )

            return
        }

        if classes.contains("channel-reference") || type == "channel-reference" {
            pending = PendingSpan(
                kind: .channelReference(channelId: tag.intAttribute("data-channel-id")),
                fallback: tag.attribute("data-name").map { "#\($0)" } ?? ""
            )

            return
        }

        if type == "emoji" {
            append(.emoji(name: tag.attribute("data-name") ?? "", src: nil))
            skipDepth += 1

            return
        }

        if classes.contains("plugin-command") {
            append(.pluginCommand(tag.attribute("data-name") ?? ""))
            skipDepth += 1
        }
    }

    private mutating func closeSpan() {
        if let pending {
            let label = pending.text.isEmpty ? pending.fallback : pending.text

            switch pending.kind {
            case .mention(let userId):
                append(.mention(userId: userId, label: label))
            case .channelReference(let channelId):
                append(.channelReference(channelId: channelId, label: label))
            }

            self.pending = nil

            return
        }

        if skipDepth > 0 {
            skipDepth -= 1
        }
    }

    private var currentFlags: (bold: Bool, italic: Bool, code: Bool, href: String?) {
        var flags = (bold: false, italic: false, code: false, href: String?.none)

        for tag in styles {
            switch tag.name {
            case "strong", "b":
                flags.bold = true
            case "em", "i":
                flags.italic = true
            case "code":
                flags.code = true
            case "a":
                flags.href = tag.attribute("href")
            default:
                break
            }
        }

        return flags
    }
}

private struct Tag {
    let name: String
    let isClosing: Bool
    let raw: String

    init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        isClosing = trimmed.hasPrefix("/")
        name = String(trimmed.drop(while: { $0 == "/" || $0 == "!" || $0 == "?" })
            .prefix(while: { $0.isLetter || $0.isNumber }))
            .lowercased()
        self.raw = trimmed
    }

    func attribute(_ key: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))") else {
            return nil
        }

        let range = NSRange(raw.startIndex..., in: raw)

        guard let match = regex.firstMatch(in: raw, range: range) else {
            return nil
        }

        for group in 2...4 {
            guard let valueRange = Range(match.range(at: group), in: raw) else {
                continue
            }

            return String(raw[valueRange])
        }

        return nil
    }

    func intAttribute(_ key: String) -> Int? {
        attribute(key).flatMap(Int.init)
    }

    var classNames: Set<String> {
        Set((attribute("class") ?? "").split(separator: " ").map(String.init))
    }
}
