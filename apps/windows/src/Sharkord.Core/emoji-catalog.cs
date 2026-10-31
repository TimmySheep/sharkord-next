using System.Text.Json;

namespace Sharkord.Core;

public sealed record StandardEmoji(string Name, string Emoji, string[] Shortcodes, string Group);

public static class EmojiCatalog
{
    private static readonly Lazy<IReadOnlyList<StandardEmoji>> Catalog = new(() =>
    {
        using var stream = typeof(EmojiCatalog).Assembly.GetManifestResourceStream("Sharkord.Core.emoji-catalog.json")!;
        return JsonSerializer.Deserialize<List<StandardEmoji>>(stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    });

    public static IReadOnlyList<StandardEmoji> All => Catalog.Value;

    public static string Glyph(string shortcode) => All.FirstOrDefault(emoji =>
        emoji.Shortcodes.Contains(shortcode, StringComparer.OrdinalIgnoreCase))?.Emoji ?? shortcode;

    public static IEnumerable<StandardEmoji> Search(string query)
    {
        var needle = query.Trim();
        return All.Where(emoji => emoji.Name.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
            emoji.Shortcodes.Any(code => code.Contains(needle, StringComparison.OrdinalIgnoreCase)));
    }
}
