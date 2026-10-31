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

    public static IReadOnlyList<StandardEmoji> Tones { get; } =
    [
        new("tone1", "🏻", ["tone1", "tone_light"], "components"),
        new("tone2", "🏼", ["tone2", "tone_medium_light"], "components"),
        new("tone3", "🏽", ["tone3", "tone_medium"], "components"),
        new("tone4", "🏾", ["tone4", "tone_medium_dark"], "components"),
        new("tone5", "🏿", ["tone5", "tone_dark"], "components")
    ];

    private static readonly Lazy<IReadOnlyDictionary<string, StandardEmoji>> ByShortcode = new(() =>
        All.Concat(Tones).SelectMany(emoji => emoji.Shortcodes.Select(code => (Code: code, Emoji: emoji)))
            .GroupBy(entry => entry.Code, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Emoji, StringComparer.OrdinalIgnoreCase));

    public static string? ReactionShortcode(StandardEmoji emoji) => emoji.Shortcodes.FirstOrDefault(code => code.Length is > 0 and <= 32);

    public static string Glyph(string shortcode) => ByShortcode.Value.TryGetValue(shortcode, out var emoji) ? emoji.Emoji : shortcode;

    public static IEnumerable<StandardEmoji> Search(string query)
    {
        var needle = query.Trim();
        return All.Concat(Tones).Where(emoji => emoji.Name.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
            emoji.Shortcodes.Any(code => code.Contains(needle, StringComparison.OrdinalIgnoreCase)));
    }
}
