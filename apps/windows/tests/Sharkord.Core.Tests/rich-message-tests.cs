using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class RichMessageTests
{
    [Fact]
    public void ComposerEscapesHtmlAndCreatesOnlySupportedSemanticNodes()
    {
        var html = MessageHtml.FromComposerText("**bold** *italic* `code <x>` @[A & B](user:12) #[general](channel:7) [link](https://example.com/?a=1&b=2) <script>");
        Assert.Contains("<strong>bold</strong>", html);
        Assert.Contains("<em>italic</em>", html);
        Assert.Contains("<code>code &lt;x&gt;</code>", html);
        Assert.Contains("data-user-id=\"12\"", html);
        Assert.Contains("data-channel-id=\"7\"", html);
        Assert.Contains("@A &amp; B", html);
        Assert.Contains("href=\"https://example.com/?a=1&amp;b=2\"", html);
        Assert.Contains("&lt;script&gt;", html);
    }

    [Theory]
    [InlineData("[attack](javascript:alert(1))")]
    [InlineData("[attack](data:text/html,attack)")]
    [InlineData("[attack](file:///C:/secret)")]
    public void ComposerNeverCreatesActiveLinksForUnsafeSchemes(string text)
    {
        Assert.DoesNotContain("<a ", MessageHtml.FromComposerText(text));
    }

    [Fact]
    public void NativeParserRetainsFormattingSemanticIdsAndSafeUrlEntities()
    {
        var parts = MessageHtml.Parse("<p><strong>bold</strong><br><a href=\"https://example.com/?a=1&amp;b=2\">link</a><span data-type=\"mention\" data-user-id=\"12\">@Ada</span><span data-type=\"channel-reference\" data-channel-id=\"7\"></span><span data-type=\"emoji\" data-name=\"thumbsup\">👍</span></p>");
        var children = Assert.Single(parts).Children;
        Assert.Equal(MessagePartKind.Bold, children[0].Kind);
        Assert.Equal(MessagePartKind.Break, children[1].Kind);
        Assert.Equal("https://example.com/?a=1&b=2", children[2].Target);
        Assert.Equal(12, children[3].Id);
        Assert.Equal(7, children[4].Id);
        Assert.Equal("thumbsup", children[5].Target);
    }

    [Fact]
    public void ParserDropsExecutableContentAndRejectsUntrustedImageSources()
    {
        var parts = MessageHtml.Parse("<script>secret()</script><p>&lt;b&gt;<img src=\"https://evil.invalid/track.png\" alt=\"fallback\"><a href=\"javascript:bad\">safe text</a></p>");
        Assert.DoesNotContain(parts, part => part.Text.Contains("secret"));
        var children = Assert.Single(parts).Children;
        Assert.Equal("<b>", children[0].Text);
        Assert.Null(children[1].Target);
        Assert.Null(children[2].Target);
    }

    [Fact]
    public void CodeBlocksPreserveBlankLinesAndSpoilersKeepWireSafeText()
    {
        var html = MessageHtml.FromComposerText("```\na\n\nb\n```\n||hidden||");
        Assert.Contains("<pre><code>a\n\nb</code></pre>", html);
        Assert.Contains("||hidden||", html);
        Assert.Contains(MessageHtml.Parse("<p>||hidden||</p>")[0].Children, part => part.Kind == MessagePartKind.Spoiler);
    }

    [Fact]
    public void RichEditTextKeepsSemanticReferencesAndFormattingWhenChangingAnotherWord()
    {
        const string html = "<p><strong>bold</strong> <span data-type=\"mention\" data-user-id=\"12\">@Ada</span> <span data-type=\"channel-reference\" data-channel-id=\"7\">#general</span> <span data-type=\"emoji\" data-name=\"custom_face\"><img src=\"/public/face.png\" alt=\":custom_face:\"></span></p>";
        var text = MessageHtml.ToComposerText(html);
        Assert.Contains("**bold**", text);
        Assert.Contains("@[Ada](user:12)", text);
        Assert.Contains("#[general](channel:7)", text);
        Assert.Contains(":custom_face:", text);
        var edited = MessageHtml.FromComposerText(text.Replace("bold", "changed"), new Dictionary<string, string> { ["custom_face"] = "/public/face.png" });
        Assert.Contains("data-user-id=\"12\"", edited);
        Assert.Contains("data-channel-id=\"7\"", edited);
        Assert.Contains("<strong>changed</strong>", edited);
    }

    [Fact]
    public void ShortcodeNodesAndImageAttributesAreEncodedWithoutDoubleDecoding()
    {
        var html = MessageHtml.FromComposerText(":custom:", new Dictionary<string, string> { ["custom"] = "/public/emoji.png?a=1&token=\"quote\"" });
        Assert.Contains("&amp;token=&quot;quote&quot;", html);
        var parsed = Assert.Single(MessageHtml.Parse(html)).Children;
        Assert.Equal("custom", Assert.Single(parsed).Target);
        Assert.Equal("/public/emoji.png?a=1&token=\"quote\"", parsed[0].Children[0].Target);
    }

    [Fact]
    public void ReactionChoicesUseSupportedLengthAliasesWithoutTruncatingIdentity()
    {
        Assert.Equal("short", EmojiCatalog.ReactionShortcode(new StandardEmoji("long", "x", [new string('x', 33), "short"], "symbols")));
        Assert.Null(EmojiCatalog.ReactionShortcode(new StandardEmoji("long", "x", [new string('x', 33)], "symbols")));
        Assert.Equal("🏿", EmojiCatalog.Glyph("tone_dark"));
    }
}
