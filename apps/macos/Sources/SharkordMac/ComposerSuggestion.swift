import Foundation
import SharkordCore

/// What a suggestion menu is currently offering.
enum ComposerSuggestionKind: Hashable {
    case mention
    case channel
    case emoji
    case command
}

/// One selectable row in the suggestion menu.
struct ComposerSuggestionItem: Identifiable, Hashable {
    enum ID: Hashable {
        case user(Int)
        case channel(Int)
        case emoji(String)
        case command(String)
    }

    let id: ID
    let kind: ComposerSuggestionKind
    let label: String
    let detail: String?
    let glyph: String?
    let insert: String
}

/// An emoji the menu can offer: a server custom emoji or a bundled standard one.
struct EmojiCandidate: Hashable {
    let name: String
    let glyph: String
    let isCustom: Bool
}

/// The `@`, `#`, `:`, `/` token the caret sits inside, and the region it occupies so accepting a
/// suggestion can replace exactly that token.
struct ComposerSuggestionQuery: Hashable {
    let kind: ComposerSuggestionKind
    let trigger: Character
    let text: String
    let range: Range<Int>
}

/// Pure parsing and ranking for the composer's suggestion menu. Keeping it free of AppKit and
/// SwiftUI makes the trigger detection and the prefix-first ranking straightforward to test.
enum ComposerSuggestion {
    private static let limits: [ComposerSuggestionKind: Int] = [
        .mention: 10,
        .channel: 10,
        .emoji: 5,
        .command: 10
    ]

    private static func kind(for trigger: Character) -> ComposerSuggestionKind? {
        switch trigger {
        case "@": return .mention
        case "#": return .channel
        case ":": return .emoji
        case "/": return .command
        default: return nil
        }
    }

    private static func index(_ utf16Offset: Int, in text: String) -> String.Index {
        text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset)
    }

    private static func isWhitespace(_ unit: UTF16.CodeUnit) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// finds the trigger token the caret is inside. a trigger only counts at the start of a word
    /// (start of text or after whitespace), so `https://x` never opens a command menu on its
    /// `:`. a lone trigger is still a valid query, so the menu can show every candidate before
    /// you type anything.
    static func query(in text: String, caret: Int) -> ComposerSuggestionQuery? {
        let units = Array(text.utf16)
        guard caret > 0, caret <= units.count else { return nil }

        var start = caret
        while start > 0, !isWhitespace(units[start - 1]) {
            start -= 1
        }

        guard start < caret,
              let triggerUnit = UnicodeScalar(units[start]),
              let kind = kind(for: Character(triggerUnit)) else { return nil }

        let queryText = String(text[index(start + 1, in: text)..<index(caret, in: text)])

        return ComposerSuggestionQuery(kind: kind, trigger: Character(triggerUnit), text: queryText, range: start..<caret)
    }

    /// ranks candidates the way the web client's filter-by-query does: prefix matches before
    /// substring matches, then shorter names first, then alphabetical.
    static func filter<T>(_ items: [T], query: String, limit: Int, label: (T) -> String) -> [T] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return Array(items.prefix(limit)) }

        var scored: [(rank: Int, length: Int, text: String, item: T)] = []
        for item in items {
            let name = label(item).lowercased()
            let rank: Int
            if name.hasPrefix(needle) {
                rank = 0
            } else if name.contains(needle) {
                rank = 1
            } else {
                continue
            }
            scored.append((rank, name.count, name, item))
        }

        scored.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.length != b.length { return a.length < b.length }
            return a.text < b.text
        }

        return Array(scored.prefix(limit).map(\.item))
    }

    static func items(
        for query: ComposerSuggestionQuery,
        users: [(id: Int, name: String)],
        channels: [(id: Int, name: String)],
        emojis: [EmojiCandidate],
        commands: [PluginCommand]
    ) -> [ComposerSuggestionItem] {
        switch query.kind {
        case .mention:
            let limit = limits[.mention] ?? 10
            return filter(users, query: query.text, limit: limit, label: \.name).map { user in
                ComposerSuggestionItem(
                    id: .user(user.id),
                    kind: .mention,
                    label: user.name,
                    detail: nil,
                    glyph: nil,
                    insert: "@[\(user.name)](user:\(user.id)) "
                )
            }
        case .channel:
            let limit = limits[.channel] ?? 10
            return filter(channels, query: query.text, limit: limit, label: \.name).map { channel in
                ComposerSuggestionItem(
                    id: .channel(channel.id),
                    kind: .channel,
                    label: channel.name,
                    detail: nil,
                    glyph: nil,
                    insert: "#[\(channel.name)](channel:\(channel.id)) "
                )
            }
        case .emoji:
            let limit = limits[.emoji] ?? 5
            return filter(emojis, query: query.text, limit: limit, label: \.name).map { emoji in
                ComposerSuggestionItem(
                    id: .emoji(emoji.name),
                    kind: .emoji,
                    label: ":\(emoji.name):",
                    detail: nil,
                    glyph: emoji.isCustom ? nil : emoji.glyph,
                    insert: ":\(emoji.name): "
                )
            }
        case .command:
            let limit = limits[.command] ?? 10
            return filter(commands, query: query.text, limit: limit, label: \.name).map { command in
                ComposerSuggestionItem(
                    id: .command(command.id),
                    kind: .command,
                    label: "/\(command.name)",
                    detail: command.description,
                    glyph: nil,
                    insert: "/\(command.name) "
                )
            }
        }
    }
}
