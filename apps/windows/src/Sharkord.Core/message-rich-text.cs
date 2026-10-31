using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Sharkord.Core;

public enum MessagePartKind
{
    Text, Group, Paragraph, Break, Bold, Italic, Underline, Strike, Code, CodeBlock,
    Link, Mention, Channel, Emoji, Image, Spoiler
}

public sealed record MessagePart(MessagePartKind Kind, string Text = "", string? Target = null, int? Id = null)
{
    public List<MessagePart> Children { get; } = [];
    public bool IsEmojiImage { get; init; }
}

public static partial class MessageHtml
{
    public static bool IsSafeLink(string? value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "mailto";

    public static string? SafeImageReference(string? value)
    {
        if (value?.StartsWith("/public/", StringComparison.Ordinal) == true) { return value; }
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) { return null; }
        if (uri.Host.Equals("cdn.jsdelivr.net", StringComparison.OrdinalIgnoreCase)) { return uri.AbsoluteUri; }
        return uri.AbsolutePath.StartsWith("/public/", StringComparison.Ordinal) ? uri.PathAndQuery : null;
    }

    public static IReadOnlyList<MessagePart> Parse(string html)
    {
        var root = new MessagePart(MessagePartKind.Group);
        var stack = new List<(string Tag, MessagePart Part)> { ("", root) };
        var safe = Regex.Replace(html, @"<(script|style|iframe|object)\b[^>]*>.*?(?:</\1\s*>|$)", "", RegexOptions.IgnoreCase | RegexOptions.Singleline);
        foreach (Match token in Regex.Matches(safe, @"<[^>]*>|[^<]+|<", RegexOptions.Singleline))
        {
            var value = token.Value;
            var current = stack[^1].Part;
            if (!value.StartsWith('<') || value == "<")
            {
                var text = WebUtility.HtmlDecode(value);
                if (stack.Count == 1 && string.IsNullOrWhiteSpace(text)) { continue; }
                if (stack.Any(entry => entry.Part.Kind is MessagePartKind.Code or MessagePartKind.CodeBlock))
                {
                    current.Children.Add(new(MessagePartKind.Text, text));
                }
                else { AddSpoilerText(current.Children, text); }
                continue;
            }
            var tagMatch = Regex.Match(value, @"^<\s*(/?)\s*([a-z][\w-]*)", RegexOptions.IgnoreCase);
            if (!tagMatch.Success) { continue; }
            var tag = tagMatch.Groups[2].Value.ToLowerInvariant();
            if (tagMatch.Groups[1].Length > 0)
            {
                var closing = stack.FindLastIndex(entry => entry.Tag == tag);
                if (closing > 0) { stack.RemoveRange(closing, stack.Count - closing); }
                continue;
            }
            var attributes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match attribute in Regex.Matches(value, "([\\w-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"))
            {
                var content = attribute.Groups[2].Success ? attribute.Groups[2].Value : attribute.Groups[3].Value;
                if (attribute.Groups[4].Success) { content = attribute.Groups[4].Value; }
                attributes[attribute.Groups[1].Value] = WebUtility.HtmlDecode(content);
            }
            var kind = tag switch
            {
                "p" or "div" or "li" => MessagePartKind.Paragraph,
                "br" => MessagePartKind.Break,
                "strong" or "b" => MessagePartKind.Bold,
                "em" or "i" => MessagePartKind.Italic,
                "u" => MessagePartKind.Underline,
                "s" or "del" => MessagePartKind.Strike,
                "code" => MessagePartKind.Code,
                "pre" => MessagePartKind.CodeBlock,
                "a" => MessagePartKind.Link,
                "img" => MessagePartKind.Image,
                _ => MessagePartKind.Group
            };
            string? target = null;
            int? id = null;
            if (tag == "a" && attributes.TryGetValue("href", out var href) && IsSafeLink(href)) { target = href; }
            if (tag == "img") { target = SafeImageReference(attributes.GetValueOrDefault("src")); }
            if (tag == "span")
            {
                var type = attributes.GetValueOrDefault("data-type");
                if (type == "mention") { kind = MessagePartKind.Mention; id = ParseId(attributes.GetValueOrDefault("data-user-id")); }
                if (type == "channel-reference") { kind = MessagePartKind.Channel; id = ParseId(attributes.GetValueOrDefault("data-channel-id")); }
                if (type == "emoji") { kind = MessagePartKind.Emoji; target = attributes.GetValueOrDefault("data-name"); }
            }
            var part = new MessagePart(kind, attributes.GetValueOrDefault("alt") ?? "", target, id)
            {
                IsEmojiImage = tag == "img" && attributes.GetValueOrDefault("class")?.Split(' ').Contains("emoji-image") == true
            };
            current.Children.Add(part);
            if (tag is not ("br" or "img" or "hr" or "input" or "meta" or "link") && !value.EndsWith("/>"))
            {
                // malformed input stays bounded; server messages are limited to 10,000 characters
                if (stack.Count < 64) { stack.Add((tag, part)); }
            }
        }
        return root.Children;
    }

    private static int? ParseId(string? value) => int.TryParse(value, out var id) && id > 0 ? id : null;

    private static void AddSpoilerText(List<MessagePart> parts, string text)
    {
        var position = 0;
        foreach (Match match in Regex.Matches(text, @"\|\|(.+?)\|\|", RegexOptions.Singleline))
        {
            if (match.Index > position) { parts.Add(new(MessagePartKind.Text, text[position..match.Index])); }
            parts.Add(new(MessagePartKind.Spoiler, match.Groups[1].Value));
            position = match.Index + match.Length;
        }
        if (position < text.Length) { parts.Add(new(MessagePartKind.Text, text[position..])); }
    }

    public static string FromComposerText(string text, IReadOnlyDictionary<string, string>? customEmojis = null)
    {
        var normalized = text.ReplaceLineEndings("\n");
        var output = new StringBuilder();
        var position = 0;
        foreach (Match code in Regex.Matches(normalized, @"```[^\n]*\n(.*?)\n```", RegexOptions.Singleline))
        {
            if (code.Index > position) { output.Append("<p>").Append(FormatInline(normalized[position..code.Index], customEmojis)).Append("</p>"); }
            output.Append("<pre><code>").Append(Escape(code.Groups[1].Value)).Append("</code></pre>");
            position = code.Index + code.Length;
        }
        if (position < normalized.Length || output.Length == 0)
        {
            output.Append("<p>").Append(FormatInline(normalized[position..], customEmojis)).Append("</p>");
        }
        return output.ToString();
    }

    private static string FormatInline(string text, IReadOnlyDictionary<string, string>? customEmojis, int depth = 0)
    {
        if (depth > 8) { return Escape(text); }
        const string pattern = @"`(?<code>[^`\n]+)`|\*\*(?<bold>[^\n]+?)\*\*|\*(?<italic>[^*\n]+)\*|(?<mark>[@#])\[(?<label>[^\]\n]+)\]\((?<kind>user|channel):(?<id>[1-9]\d*)\)|\[(?<linklabel>[^\]\n]+)\]\((?<url>[^\s)]+)\)|:(?<emoji>[\w+.-]+):|(?<bare>https?://[^\s<>]+)";
        var output = new StringBuilder();
        var position = 0;
        foreach (Match match in Regex.Matches(text, pattern))
        {
            output.Append(Escape(text[position..match.Index]).Replace("\n", "<br class=\"hard-break\">"));
            if (match.Groups["code"].Success) { output.Append("<code>").Append(Escape(match.Groups["code"].Value)).Append("</code>"); }
            else if (match.Groups["bold"].Success) { output.Append("<strong>").Append(FormatInline(match.Groups["bold"].Value, customEmojis, depth + 1)).Append("</strong>"); }
            else if (match.Groups["italic"].Success) { output.Append("<em>").Append(FormatInline(match.Groups["italic"].Value, customEmojis, depth + 1)).Append("</em>"); }
            else if (match.Groups["mark"].Success)
            {
                var isUser = match.Groups["kind"].Value == "user";
                var type = isUser ? "mention" : "channel-reference";
                var attribute = isUser ? "data-user-id" : "data-channel-id";
                output.Append($"<span data-type=\"{type}\" {attribute}=\"{match.Groups["id"].Value}\" class=\"{type}\">")
                    .Append(Escape(match.Groups["mark"].Value + match.Groups["label"].Value)).Append("</span>");
            }
            else if (match.Groups["emoji"].Success)
            {
                var name = match.Groups["emoji"].Value;
                if (customEmojis?.TryGetValue(name, out var image) == true && SafeImageReference(image) is { } src)
                {
                    output.Append($"<span data-type=\"emoji\" data-name=\"{EscapeAttribute(name)}\"><img class=\"emoji-image\" src=\"{EscapeAttribute(src)}\" alt=\":{EscapeAttribute(name)}:\"></span>");
                }
                else
                {
                    var glyph = EmojiCatalog.Glyph(name);
                    if (glyph == name) { output.Append(Escape(match.Value)); }
                    else { output.Append($"<span data-type=\"emoji\" data-name=\"{EscapeAttribute(name)}\">{Escape(glyph)}</span>"); }
                }
            }
            else
            {
                var url = match.Groups["url"].Success ? match.Groups["url"].Value : match.Groups["bare"].Value;
                var label = match.Groups["linklabel"].Success ? match.Groups["linklabel"].Value : url;
                if (IsSafeLink(url)) { output.Append($"<a href=\"{EscapeAttribute(url)}\" target=\"_blank\" rel=\"noopener noreferrer\">{Escape(label)}</a>"); }
                else { output.Append(Escape(match.Value)); }
            }
            position = match.Index + match.Length;
        }
        output.Append(Escape(text[position..]).Replace("\n", "<br class=\"hard-break\">"));
        return output.ToString();
    }

    public static string ToComposerText(string html) => string.Join("\n", Parse(html).Select(EditablePart));

    private static string EditablePart(MessagePart part)
    {
        var children = string.Concat(part.Children.Select(EditablePart));
        if (part.Kind == MessagePartKind.Text) { return part.Text; }
        if (part.Kind == MessagePartKind.Break) { return "\n"; }
        if (part.Kind == MessagePartKind.Bold) { return $"**{children}**"; }
        if (part.Kind == MessagePartKind.Italic) { return $"*{children}*"; }
        if (part.Kind == MessagePartKind.CodeBlock) { return $"```\n{string.Concat(part.Children.Select(PlainPart))}\n```"; }
        if (part.Kind == MessagePartKind.Code) { return $"`{children}`"; }
        if (part.Kind == MessagePartKind.Spoiler) { return $"||{part.Text}||"; }
        if (part.Kind == MessagePartKind.Mention && part.Id is { } userId) { return $"@[{children.TrimStart('@').Replace("]", ")")}](user:{userId})"; }
        if (part.Kind == MessagePartKind.Channel && part.Id is { } channelId)
        {
            var label = children.TrimStart('#');
            if (label.Length == 0) { label = channelId.ToString(); }
            return $"#[{label.Replace("]", ")")}](channel:{channelId})";
        }
        if (part.Kind == MessagePartKind.Emoji && part.Target is { } name) { return $":{name}:"; }
        if (part.Kind == MessagePartKind.Link && part.Target is { } href) { return $"[{children.Replace("]", ")")}]({href})"; }
        if (part.Kind == MessagePartKind.Image) { return part.Text; }
        return children;
    }

    private static string PlainPart(MessagePart part) => part.Kind == MessagePartKind.Break ? "\n" : part.Text + string.Concat(part.Children.Select(PlainPart));

    private static string EscapeAttribute(string value) => Escape(value).Replace("\"", "&quot;").Replace("'", "&#39;");
}
