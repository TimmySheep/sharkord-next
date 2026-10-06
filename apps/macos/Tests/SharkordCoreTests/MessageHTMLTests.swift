import Foundation
import Testing

@testable import SharkordCore

@Suite
struct MessageHTMLTests {
    @Test
    func plainTextEscapesAndKeepsLineStructure() {
        #expect(MessageHTML.fromPlainText("hello") == "<p>hello</p>")
        #expect(MessageHTML.fromPlainText("<b>") == "<p>&lt;b&gt;</p>")

        let html = MessageHTML.fromPlainText("a < b\nc & d")

        #expect(html == "<p>a &lt; b<br class=\"hard-break\">c &amp; d</p>")
    }

    @Test
    func prepareLinkifiesAndNormalizesTrailingBreaks() {
        let prepared = MessageHTML.prepare(
            "<p>see https://sharkord.dev/x<br class=\"hard-break\"></p><p>next</p>"
        )

        #expect(prepared.contains("<a href=\"https://sharkord.dev/x\""))
        #expect(prepared.contains("</p><p></p><p>next</p>"))
    }

    @Test
    func linkifyLeavesTagsAlone() {
        let html = MessageHTML.linkify(
            "<a href=\"https://a.example\">https://a.example</a> plain https://b.example"
        )

        // the existing anchor is untouched and the bare url gets one anchor of its own
        #expect(html.filter { $0 == "<" }.count == 4)
        #expect(html.contains("plain <a href=\"https://b.example\""))
        #expect(!html.contains("<a href=\"https://a.example\"><a"))
    }

    @Test
    func toPlainTextKeepsMentionsAndDropsEmojiAndChannelRefs() {
        let html = """
        <p>hi <span class="mention" data-user-id="7" data-name="Ada">@Ada</span> \
        <img class="emoji-image" src="/public/emoji/1" alt=":party:"> \
        <span class="channel-reference" data-channel-id="3" data-name="general">#general</span></p>
        """

        #expect(MessageHTML.toPlainText(html) == "hi @Ada")
    }

    @Test
    func toPlainTextJoinsBlocksAndLineBreaks() {
        let html = "<p>one</p><p>two<br class=\"hard-break\">three</p>"

        #expect(MessageHTML.toPlainText(html) == "one\ntwo\nthree")
    }

    @Test
    func emptyMessageDetection() {
        #expect(MessageHTML.isEmpty(nil))
        #expect(MessageHTML.isEmpty(""))
        #expect(MessageHTML.isEmpty("<p></p>"))
        #expect(MessageHTML.isEmpty("<p>   </p>"))
        #expect(!MessageHTML.isEmpty("<p>x</p>"))
        #expect(!MessageHTML.isEmpty("<img class=\"emoji-image\" src=\"/public/emoji/1\">"))
    }

    @Test
    func emojiOnlyMessageDetection() {
        #expect(MessageHTML.isEmojiOnly("<img class=\"emoji-image\" src=\"/public/emoji/1\" alt=\":party:\">"))
        #expect(MessageHTML.isEmojiOnly("<p><img class=\"emoji-image\" src=\"/public/emoji/1\"></p>"))
        #expect(!MessageHTML.isEmojiOnly("<p>text</p>"))
        #expect(!MessageHTML.isEmojiOnly("<img class=\"emoji-image\" src=\"/public/emoji/1\"> <p>hi</p>"))
    }

    @Test
    func parsesInlineStylesAndLinks() {
        let html = "<p><strong>bold</strong> <em>it</em> <code>code</code> <a href=\"https://x.dev\">link</a></p>"
        let document = MessageHTML.parse(html)

        #expect(document.blocks.count == 1)

        let spans = document.blocks[0].spans
        #expect(spans.count == 7)
        #expect(spans[0].bold == true)
        #expect(spans[2].italic == true)
        #expect(spans[4].code == true)
        #expect(spans[6].href == "https://x.dev")
    }

    @Test
    func parsesMentionsEmojiAndChannelReferences() {
        let html = """
        <p><span class="mention" data-user-id="4" data-name="Ada">@Ada</span> \
        <span class="channel-reference" data-channel-id="9" data-name="dev">#dev</span> \
        <img class="emoji-image" src="/public/emoji/2" alt=":wave:"></p>
        """
        let document = MessageHTML.parse(html)
        let spans = document.blocks[0].spans

        #expect(spans.count == 5)
        #expect(spans[0].content == .mention(userId: 4, label: "@Ada"))
        #expect(spans[2].content == .channelReference(channelId: 9, label: "#dev"))
        #expect(spans[4].content == .emoji(name: "wave", src: "/public/emoji/2"))
    }

    @Test
    func parsesCodeBlock() {
        let html = "<pre><code>let x = 1</code></pre>"
        let document = MessageHTML.parse(html)

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].kind == .code)
    }

    @Test
    func builderMarkupMatchesTheWebClient() {
        #expect(MessageHTML.mention(userId: 7, name: "Ada")
            == "<span class=\"mention\" data-user-id=\"7\" data-name=\"Ada\">@Ada</span>")
        #expect(MessageHTML.channelReference(channelId: 3, name: "general")
            == "<span class=\"channel-reference\" data-channel-id=\"3\" data-name=\"general\">#general</span>")
        #expect(MessageHTML.emoji(name: "party", src: "/public/emoji/1")
            == "<img class=\"emoji-image\" src=\"/public/emoji/1\" alt=\":party:\">")
    }

    @Test
    func decodesEntitiesIncludingNumericOnes() {
        #expect(MessageHTML.decodeEntities("a &amp; b &lt;c&gt; &#65; &#x42;") == "a & b <c> A B")
    }
}
