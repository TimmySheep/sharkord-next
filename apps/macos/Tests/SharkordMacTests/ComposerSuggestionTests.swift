import Foundation
import Testing

@testable import SharkordMac
import SharkordCore

@Suite
struct ComposerSuggestionTests {
    @Test func detectsMentionChannelEmojiAndCommandTriggers() {
        let mention = ComposerSuggestion.query(in: "hi @ad", caret: 6)
        #expect(mention?.kind == .mention)
        #expect(mention?.text == "ad")
        #expect(mention?.range == 3..<6)

        let channel = ComposerSuggestion.query(in: "see #ge", caret: 7)
        #expect(channel?.kind == .channel)
        #expect(channel?.text == "ge")

        let emoji = ComposerSuggestion.query(in: ":smi", caret: 4)
        #expect(emoji?.kind == .emoji)
        #expect(emoji?.text == "smi")

        let command = ComposerSuggestion.query(in: "/ki", caret: 3)
        #expect(command?.kind == .command)
        #expect(command?.text == "ki")
    }

    @Test func aLoneTriggerIsAValidEmptyQuery() {
        let query = ComposerSuggestion.query(in: "hi @", caret: 4)
        #expect(query?.kind == .mention)
        #expect(query?.text == "")
        #expect(query?.range == 3..<4)
    }

    @Test func aTriggerOnlyCountsAtTheStartOfAWord() {
        #expect(ComposerSuggestion.query(in: "https://x", caret: 9) == nil)
        #expect(ComposerSuggestion.query(in: "a@b", caret: 3) == nil)
        #expect(ComposerSuggestion.query(in: "hi", caret: 2) == nil)
    }

    @Test func filterRanksPrefixBeforeSubstringAndShorterFirst() {
        let items = ["alpha", "alto", "beta", "al"]
        let ranked = ComposerSuggestion.filter(items, query: "al", limit: 10, label: { $0 })
        #expect(ranked == ["al", "alto", "alpha"])

        let limited = ComposerSuggestion.filter(items, query: "a", limit: 2, label: { $0 })
        #expect(limited.count == 2)
    }

    @Test func mentionAndChannelItemsCarryRoundTrippableInserts() {
        let users = [(id: 7, name: "Ada")]
        let channels = [(id: 3, name: "general")]
        let query = ComposerSuggestionQuery(kind: .mention, trigger: "@", text: "ad", range: 0..<3)
        let mentions = ComposerSuggestion.items(for: query, users: users, channels: channels, emojis: [], commands: [])
        #expect(mentions.first?.insert == "@[Ada](user:7) ")

        let channelQuery = ComposerSuggestionQuery(kind: .channel, trigger: "#", text: "ge", range: 0..<3)
        let channelItems = ComposerSuggestion.items(for: channelQuery, users: users, channels: channels, emojis: [], commands: [])
        #expect(channelItems.first?.insert == "#[general](channel:3) ")
    }

    @Test func emojiItemsPreferTheShortcodeAndHideCustomGlyphs() {
        let emojis = [
            EmojiCandidate(name: "party", glyph: "🎉", isCustom: true),
            EmojiCandidate(name: "smile", glyph: "😄", isCustom: false)
        ]
        let query = ComposerSuggestionQuery(kind: .emoji, trigger: ":", text: "", range: 0..<1)
        let items = ComposerSuggestion.items(for: query, users: [], channels: [], emojis: emojis, commands: [])

        #expect(items.first?.label == ":party:")
        #expect(items.first?.insert == ":party: ")
        #expect(items.first?.glyph == nil)
        #expect(items.last?.glyph == "😄")
    }

    @Test func commandItemsShowDescription() throws {
        let payload = Data(#"{"pluginId":"p","name":"roll","description":"roll a die"}"#.utf8)
        let command = try JSONDecoder().decode(PluginCommand.self, from: payload)
        let query = ComposerSuggestionQuery(kind: .command, trigger: "/", text: "ro", range: 0..<3)
        let items = ComposerSuggestion.items(for: query, users: [], channels: [], emojis: [], commands: [command])

        #expect(items.first?.label == "/roll")
        #expect(items.first?.detail == "roll a die")
        #expect(items.first?.insert == "/roll ")
    }
}
