using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class FilePreferencesTests
{
    [Fact]
    public void PreferencesSurviveNewInstancesAndRetainTypedValues()
    {
        var path = Path.Combine(Path.GetTempPath(), $"cove-preferences-{Guid.NewGuid():N}.json");
        try
        {
            var first = new FilePreferences(path);
            first.Set("notifications.enabled", true);
            first.Set("voice.noiseSuppressionMix", 37.5);
            first.Set("channel", 7);
            first.Set("shortcuts", "{\"send\":13}");
            var restored = new FilePreferences(path);
            Assert.True(restored.Get("notifications.enabled", false));
            Assert.Equal(37.5, restored.Get("voice.noiseSuppressionMix", 100d));
            Assert.Equal(7, restored.Get("channel", 0));
            Assert.Equal("{\"send\":13}", restored.Get("shortcuts", ""));
            Assert.Equal(12, restored.Get("missing", 12));
            restored.Remove("channel");
            Assert.Equal(0, first.Get("channel", 0));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void MalformedAndWrongTypedPreferencesFallBackWithoutBreakingLaterWrites()
    {
        var path = Path.Combine(Path.GetTempPath(), $"cove-preferences-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, "not json");
            var preferences = new FilePreferences(path);
            Assert.True(preferences.Get("flag", true));
            preferences.Set("flag", "wrong type");
            Assert.False(preferences.Get("flag", false));
            preferences.Set("flag", true);
            Assert.True(new FilePreferences(path).Get("flag", false));
        }
        finally { File.Delete(path); }
    }
}
