using System.Text.RegularExpressions;

namespace Sharkord.Core;

/// <summary>
/// Converts between the plain composer text and the HTML the server stores. The web
/// editor sends HTML; a native field only has to escape and keep the line structure,
/// which the server's sanitizer allows as <c>&lt;p&gt;</c> and
/// <c>&lt;br class="hard-break"&gt;</c>.
/// </summary>
public static partial class MessageHtml
{
    public static string FromPlainText(string text)
    {
        var lines = text.Replace("\r\n", "\n").Split('\n');

        return string.Join(
            "<br class=\"hard-break\">",
            lines.Select(line => $"<p>{Escape(line)}</p>")
        );
    }

    public static string ToPlainText(string html)
    {
        var output = html
            .Replace("<br class=\"hard-break\">", "\n")
            .Replace("<br>", "\n")
            .Replace("</p><p>", "\n")
            .Replace("<p>", "")
            .Replace("</p>", "");

        output = TagRegex().Replace(output, "");

        return DecodeEntities(output);
    }

    private static string Escape(string text) => text
        .Replace("&", "&amp;")
        .Replace("<", "&lt;")
        .Replace(">", "&gt;");

    private static string DecodeEntities(string text) => text
        .Replace("&lt;", "<")
        .Replace("&gt;", ">")
        .Replace("&quot;", "\"")
        .Replace("&#39;", "'")
        .Replace("&amp;", "&");

    [GeneratedRegex("<[^>]+>")]
    private static partial Regex TagRegex();
}
