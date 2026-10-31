using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class EmojiCatalogTests
{
    [Fact]
    public void CatalogIncludesTheWebStandardSetAndAliases()
    {
        Assert.True(EmojiCatalog.All.Count > 1800);
        Assert.Equal("👍", EmojiCatalog.Glyph("thumbsup"));
        Assert.Equal("👍", EmojiCatalog.Glyph("+1"));
        Assert.Equal("unknown_custom_name", EmojiCatalog.Glyph("unknown_custom_name"));
    }

    [Fact]
    public void SearchMatchesNamesAndShortcodeAliasesWithoutCaseSensitivity()
    {
        Assert.Contains(EmojiCatalog.Search("THUMBSUP"), emoji => emoji.Emoji == "👍");
        Assert.Contains(EmojiCatalog.Search("rocket"), emoji => emoji.Emoji == "🚀");
        Assert.DoesNotContain(EmojiCatalog.All, emoji => string.IsNullOrWhiteSpace(emoji.Emoji));
    }
}
