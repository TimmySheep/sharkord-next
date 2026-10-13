using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class PushToTalkStateTests
{
    [Fact]
    public void TemporarilyUnmutesOnlyWhenAudioCanBePublishedAndRestoresMute()
    {
        var state = new PushToTalkState();

        Assert.True(state.Press(canPublishAudio: true, microphoneMuted: true));
        Assert.False(state.Press(canPublishAudio: true, microphoneMuted: true));
        Assert.True(state.Release());
        Assert.False(state.Release());
    }

    [Fact]
    public void DoesNotChangeAnAlreadyUnmutedMicrophone()
    {
        var state = new PushToTalkState();

        Assert.False(state.Press(canPublishAudio: true, microphoneMuted: false));
        Assert.False(state.Release());
    }

    [Fact]
    public void DoesNotUnmuteWithoutPublishPermission()
    {
        var state = new PushToTalkState();

        Assert.False(state.Press(canPublishAudio: false, microphoneMuted: true));
        Assert.False(state.Release());
    }
}
