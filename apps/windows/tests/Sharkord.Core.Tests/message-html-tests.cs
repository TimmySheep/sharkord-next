using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class MessageHtmlTests
{
    [Theory]
    [InlineData("a\nb", "<p>a<br class=\"hard-break\">b</p>")]
    [InlineData("a\r\nb", "<p>a<br class=\"hard-break\">b</p>")]
    [InlineData("<b> & \"quote\"", "<p>&lt;b&gt; &amp; \"quote\"</p>")]
    public void ComposerUsesTheWebEditorsSingleBlockHardBreaks(string text, string html)
    {
        Assert.Equal(html, MessageHtml.FromPlainText(text));
    }

    [Theory]
    [InlineData("<p>a<br class=\"hard-break\">b</p>", "a\nb")]
    [InlineData("<p>a<br />b<br/>c</p>", "a\nb\nc")]
    [InlineData("<p>one</p>\n<p>two</p>", "one\ntwo")]
    [InlineData("<p>a</p><p></p><p>b</p>", "a\n\nb")]
    [InlineData("<pre><code>a\nb</code></pre><p>c</p>", "a\nb\nc")]
    [InlineData("<p>&#x1F30A; &#169; &nbsp; &amp;lt;b&amp;gt;</p>", "🌊 © \u00a0 &lt;b&gt;")]
    [InlineData("<p>Hello <span class=\"mention\" data-user-id=\"1\">@Ada</span> <img class=\"emoji-image\" alt=\":wave:\" src=\"/public/emoji.png\"></p>", "Hello @Ada :wave:")]
    public void PlainTextFallbackKeepsVisibleTextAndLineStructure(string html, string expected)
    {
        Assert.Equal(expected, MessageHtml.ToPlainText(html));
    }
}
