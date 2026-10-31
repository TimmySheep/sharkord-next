using System.Reflection;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class VoiceRecoveryTests
{
    [Theory]
    [InlineData(SessionPhase.Connected)]
    [InlineData(SessionPhase.Connecting)]
    public async Task UnexpectedDisconnectClearsVoiceBeforeNotifyingObservers(SessionPhase phase)
    {
        using var subscriptions = new CancellationTokenSource();
        await using var session = new SharkordSession();
        var subscriptionToken = subscriptions.Token;
        SetVoice(session, 7, subscriptions);
        typeof(SharkordSession).GetProperty(nameof(SharkordSession.Phase))!.SetValue(session, phase);
        int? observedVoice = 7;
        session.Changed += () => observedVoice = session.CurrentVoiceChannelId;

        // no credentials are supplied, so this covers cleanup without opening a reconnect socket
        typeof(SharkordSession).GetMethod("HandleUnexpectedDisconnect", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(session, [new IOException("Connection lost")]);

        Assert.Equal(SessionPhase.Failed, session.Phase);
        Assert.Null(session.CurrentVoiceChannelId);
        Assert.Null(observedVoice);
        Assert.True(subscriptionToken.IsCancellationRequested);
        Assert.Null(Field("_voiceSubscriptions").GetValue(session));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task LeaveClearsLocalVoiceEvenWhenServerAlreadyRemovedIt(bool serverRejects)
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            using var subscriptions = new CancellationTokenSource();
            await using var session = new SharkordSession();
            var subscriptionToken = subscriptions.Token;
            SetVoice(session, 7, subscriptions);
            Field("_client").SetValue(session, client);
            int? observedVoice = 7;
            session.Changed += () => observedVoice = session.CurrentVoiceChannelId;
            try
            {
                var leaving = session.LeaveVoiceAsync(token);
                var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
                Assert.Equal("voice.leave", request["params"]!["path"]!.GetValue<string>());
                await WebSocketConformanceTests.SendAsync(server, Response(request, serverRejects), token);
                if (serverRejects)
                {
                    var error = await Assert.ThrowsAsync<TrpcClientError>(() => leaving);
                    Assert.Equal("BAD_REQUEST", error.Code);
                    Assert.Equal("User not in voice channel", error.Message);
                }
                else { await leaving; }

                Assert.Null(session.CurrentVoiceChannelId);
                Assert.Null(observedVoice);
                Assert.True(subscriptionToken.IsCancellationRequested);
                Assert.Null(Field("_voiceSubscriptions").GetValue(session));
            }
            finally { Field("_client").SetValue(session, null); }
        });
    }

    [Fact]
    public async Task LeaveWithoutTransportStillClearsLocalVoice()
    {
        using var subscriptions = new CancellationTokenSource();
        await using var session = new SharkordSession();
        var subscriptionToken = subscriptions.Token;
        SetVoice(session, 7, subscriptions);

        var error = await Assert.ThrowsAsync<TrpcClientError>(() => session.LeaveVoiceAsync());

        Assert.Equal("DISCONNECTED", error.Code);
        Assert.Null(session.CurrentVoiceChannelId);
        Assert.True(subscriptionToken.IsCancellationRequested);
        Assert.Null(Field("_voiceSubscriptions").GetValue(session));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task LateLeaveCannotClearAReplacementVoiceSession(bool serverRejects)
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            using var original = new CancellationTokenSource();
            using var replacement = new CancellationTokenSource();
            await using var session = new SharkordSession();
            SetVoice(session, 7, original);
            Field("_client").SetValue(session, client);
            try
            {
                var leaving = session.LeaveVoiceAsync(token);
                var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
                original.Cancel();
                // the same channel can be rejoined before the older leave response arrives
                SetVoice(session, 7, replacement);
                await WebSocketConformanceTests.SendAsync(server, Response(request, serverRejects), token);
                if (serverRejects) { await Assert.ThrowsAsync<TrpcClientError>(() => leaving); }
                else { await leaving; }

                Assert.Equal(7, session.CurrentVoiceChannelId);
                Assert.False(replacement.IsCancellationRequested);
                Assert.Same(replacement, Field("_voiceSubscriptions").GetValue(session));
            }
            finally { Field("_client").SetValue(session, null); }
        });
    }

    private static FieldInfo Field(string name) =>
        typeof(SharkordSession).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!;

    private static void SetVoice(SharkordSession session, int channelId, CancellationTokenSource subscriptions)
    {
        typeof(SharkordSession).GetProperty(nameof(SharkordSession.CurrentVoiceChannelId))!.SetValue(session, channelId);
        Field("_voiceSubscriptions").SetValue(session, subscriptions);
    }

    private static string Response(JsonNode request, bool error) => error
        ? $"{{\"id\":{request["id"]},\"error\":{{\"message\":\"User not in voice channel\",\"code\":-32600,\"data\":{{\"code\":\"BAD_REQUEST\"}}}}}}"
        : $"{{\"id\":{request["id"]},\"result\":{{\"data\":null}}}}";
}
