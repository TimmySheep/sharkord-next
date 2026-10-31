import Testing
@testable import SharkordMac

struct EmojiCatalogTests {
    @Test func catalogKeepsWebReactionIdentityAndSearchAliases() throws {
        #expect(EmojiCatalog.entries.count == 1940)
        #expect(EmojiCatalog.entries.filter { !$0.canReact }.count == 6)
        let thumb = try #require(EmojiCatalog.entries.first { $0.emoji == "👍" })
        #expect(EmojiCatalog.glyph(for: thumb.reaction) == "👍")
        #expect(EmojiCatalog.glyph(for: "thumbsup") == "👍")
        #expect(EmojiCatalog.search("thumbsup").contains { $0.emoji == "👍" })
        #expect(EmojiCatalog.search("  ROCKET ").contains { $0.emoji == "🚀" })
        #expect(EmojiCatalog.glyph(for: "unknown_custom") == "unknown_custom")
    }
}
