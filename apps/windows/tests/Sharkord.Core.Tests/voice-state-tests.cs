using System.Reflection;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class VoiceStateTests
{
    [Fact]
    public async Task VoiceSnapshotAndEventsKeepChannelsAndUserStatesIsolated()
    {
        await using var session = new SharkordSession();
        Apply(session, "ApplyVoiceSnapshot", JsonNode.Parse("""
            {"voiceMap":{"7":{"users":{"1":{"micMuted":true,"soundMuted":false,"webcamEnabled":true,"sharingScreen":false}}}},
             "externalStreamsMap":{"7":{"12":{"title":"owned stream","tracks":{"audio":true,"video":false}}}}}
            """)!.DeserializeObject<JoinResult>()!);
        Assert.True(Assert.Single(session.GetVoiceUsers(7)).State.WebcamEnabled);
        Assert.Equal("owned stream", Assert.Single(session.GetExternalStreams(7)).Value.Title);
        Apply(session, "ApplyVoiceUser", JsonNode.Parse("""{"channelId":7,"userId":1,"state":{"micMuted":false,"soundMuted":true,"webcamEnabled":false,"sharingScreen":true}}""")!);
        Apply(session, "ApplyVoiceUser", JsonNode.Parse("""{"channelId":8,"userId":2,"state":{"micMuted":true}}""")!);
        var user = Assert.Single(session.GetVoiceUsers(7));
        Assert.False(user.State.MicMuted);
        Assert.True(user.State.SoundMuted);
        Assert.True(user.State.SharingScreen);
        Apply(session, "ApplyVoiceLeave", JsonNode.Parse("""{"channelId":7,"userId":1}""")!);
        Assert.Empty(session.GetVoiceUsers(7));
        Assert.Single(session.GetVoiceUsers(8));
    }

    [Fact]
    public async Task RejoinReplacesVoiceAndExternalStreamSnapshots()
    {
        await using var session = new SharkordSession();
        Apply(session, "ApplyVoiceUser", JsonNode.Parse("""{"channelId":7,"userId":1,"state":{"micMuted":true}}""")!);
        Apply(session, "ApplyExternalStream", JsonNode.Parse("""{"channelId":7,"streamId":12,"stream":{"title":"stream"}}""")!);
        Assert.Single(session.GetExternalStreams(7));
        Apply(session, "ApplyVoiceSnapshot", new JoinResult());
        Assert.Empty(session.GetVoiceUsers(7));
        Assert.Empty(session.GetExternalStreams(7));
    }

    private static void Apply(SharkordSession session, string name, object value) =>
        typeof(SharkordSession).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(session, [value]);
}
