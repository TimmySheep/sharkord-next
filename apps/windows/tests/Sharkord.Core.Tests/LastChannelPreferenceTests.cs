using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class LastChannelPreferenceTests
{
    [Fact]
    public void UsesAStablePerServerKeyWithoutStoringTheServerAddress()
    {
        var first = LastChannelPreference.SettingKey("https://example.com/");
        var equivalent = LastChannelPreference.SettingKey("https://EXAMPLE.com");
        var other = LastChannelPreference.SettingKey("https://example.com:8443/");

        Assert.Equal(first, equivalent);
        Assert.NotEqual(first, other);
        Assert.StartsWith("app.lastSelectedChannel.", first);
        Assert.DoesNotContain("example.com", first.ToLowerInvariant());
    }

    [Theory]
    [InlineData(true, false, false, true)]
    [InlineData(false, true, false, true)]
    [InlineData(false, false, true, false)]
    [InlineData(false, false, false, false)]
    [InlineData(true, false, true, false)]
    public void RestoresOnlyTextAndDirectMessageChannels(
        bool isText,
        bool isDirectMessage,
        bool isVoice,
        bool expected
    )
    {
        Assert.Equal(expected, LastChannelPreference.CanRestoreChannel(isText, isDirectMessage, isVoice));
    }
}
