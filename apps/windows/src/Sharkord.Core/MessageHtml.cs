using System.Net;
using System.Text.RegularExpressions;

namespace Sharkord.Core;

/// <summary>
/// converts plain composer text to the web editor's block and hard-break vocabulary.
/// rich parsing and safe composer formatting live in the matching partial file.
/// </summary>
public static partial class MessageHtml
{
    public static string FromPlainText(string text)
    {
        return $"<p>{Escape(text.ReplaceLineEndings("\n")).Replace("\n", "<br class=\"hard-break\">")}</p>";
    }

    public static string ToPlainText(string html)
    {
        var output = BlockBoundaryRegex().Replace(html, "\n");
        output = BreakRegex().Replace(output, "\n");
        output = ImageRegex().Replace(output, match =>
        {
            var alt = AltRegex().Match(match.Value);
            return alt.Success ? alt.Groups[2].Value : "";
        });
        output = TagRegex().Replace(output, "");
        // decode only after removing tags, so escaped literal markup stays visible text
        return WebUtility.HtmlDecode(output);
    }

    private static string Escape(string text) => text
        .Replace("&", "&amp;")
        .Replace("<", "&lt;")
        .Replace(">", "&gt;");

    [GeneratedRegex(@"</(?:p|pre)>\s*<(?:p|pre)\b[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex BlockBoundaryRegex();

    [GeneratedRegex(@"<br\b[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex BreakRegex();

    [GeneratedRegex(@"<img\b[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex ImageRegex();

    [GeneratedRegex("\\balt\\s*=\\s*([\"'])(.*?)\\1", RegexOptions.IgnoreCase)]
    private static partial Regex AltRegex();

    [GeneratedRegex("<[^>]+>")]
    private static partial Regex TagRegex();
}
