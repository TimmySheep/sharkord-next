import Foundation
import SharkordCore

struct StandardEmoji: Decodable, Identifiable {
    let name: String
    let emoji: String
    let shortcodes: [String]
    let group: String
    var id: String { name }
    var reaction: String { shortcodes.first ?? name }
    var canReact: Bool { reaction.count <= ProtocolDefaults.reactionEmojiMaxLength }
}

enum EmojiCatalog {
    static let entries: [StandardEmoji] = {
        guard let url = Bundle.module.url(forResource: "emoji-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([StandardEmoji].self, from: data) else { return [] }
        return entries
    }()

    private static let glyphs: [String: String] = {
        var values: [String: String] = [:]
        for entry in entries {
            values[entry.name] = entry.emoji
            for shortcode in entry.shortcodes { values[shortcode] = entry.emoji }
        }
        return values
    }()

    static func glyph(for identity: String) -> String {
        glyphs[identity.trimmingCharacters(in: CharacterSet(charactersIn: ":"))] ?? identity
    }

    static func search(_ query: String) -> [StandardEmoji] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.name.contains(query) || $0.shortcodes.contains { $0.contains(query) } || $0.emoji == query
        }
    }
}
