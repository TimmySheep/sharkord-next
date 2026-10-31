using System.Reflection;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class TextNavigationTests
{
    private static void Apply(SharkordSession session, JoinResult join) =>
        typeof(SharkordSession).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [join]);

    [Fact]
    public void VoiceTypedDirectMessagesRemainTextConversations()
    {
        var channel = new SharkordChannel { Type = "VOICE", IsDm = true };
        Assert.True(channel.IsText);
        Assert.False(channel.IsVoice);
    }

    [Fact]
    public async Task RejoinInvalidatesHistoryAndPreservesValidSelection()
    {
        await using var session = new SharkordSession();
        var join = new JoinResult { Channels = [new() { Id = 7 }], ReadStates = new() { ["7"] = 3 } };
        Apply(session, join);
        typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(session, [new SharkordMessage { Id = 1, ChannelId = 7 }, false]);
        Apply(session, join);
        Assert.Empty(session.GetMessagesSnapshot(7));
        Assert.Equal(7, session.SelectedChannelId);
        Assert.Equal(3, session.UnreadCount(7));
    }

    [Fact]
    public async Task JumpAndReturnToPresentUseTargetWindowAndReplaceHistory()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            await using var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 7 }] });
            var jump = session.JumpToMessageAsync(7, 12, token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.get", request["params"]!["path"]!.GetValue<string>());
            Assert.Equal(12, request["params"]!["input"]!["targetMessageId"]!.GetValue<int>());
            await Respond(request, "{\"messages\":[{\"id\":12,\"channelId\":7}],\"hasNewer\":true}");
            await jump;
            Assert.True(session.HasNewerMessages(7));
            Assert.Equal(12, Assert.Single(session.GetMessagesSnapshot(7)).Id);
            var present = session.ReturnToPresentAsync(7, token);
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Null(request["params"]!["input"]!["targetMessageId"]);
            await Respond(request, "{\"messages\":[{\"id\":99,\"channelId\":7}],\"hasNewer\":false}");
            await present;
            Assert.False(session.HasNewerMessages(7));
            Assert.Equal(99, Assert.Single(session.GetMessagesSnapshot(7)).Id);
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, null);
            server.Abort();
            Task Respond(JsonNode request, string data) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{data}}}}}", token);
        });
    }

    [Fact]
    public async Task ThreadPagesAppendWithCursorAndNeverEnterChannelHistory()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            await using var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var load = session.LoadThreadAsync(12, cancellationToken: token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.getThread", request["params"]!["path"]!.GetValue<string>());
            Assert.Equal(12, request["params"]!["input"]!["parentMessageId"]!.GetValue<int>());
            await Respond(request, "{\"messages\":[{\"id\":13,\"channelId\":7,\"parentMessageId\":12,\"createdAt\":100}],\"nextCursor\":{\"id\":13,\"createdAt\":100}}");
            await load;
            Assert.True(session.HasMoreThreadMessages(12));
            load = session.LoadThreadAsync(12, more: true, cancellationToken: token);
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal(13, request["params"]!["input"]!["cursor"]!["id"]!.GetValue<int>());
            await Respond(request, "{\"messages\":[{\"id\":14,\"channelId\":7,\"parentMessageId\":12,\"createdAt\":200}]}");
            await load;
            Assert.Equal(new[] { 13, 14 }, session.GetThreadMessagesSnapshot(12).Select(message => message.Id));
            Assert.False(session.HasMoreThreadMessages(12));
            Assert.Empty(session.GetMessagesSnapshot(7));
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, null);
            server.Abort();
            Task Respond(JsonNode request, string data) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{data}}}}}", token);
        });
    }

    [Fact]
    public async Task LiveThreadUpdatesAndTypingStayIsolated()
    {
        await using var session = new SharkordSession();
        Apply(session, new JoinResult { OwnUserId = 1, Users = [new() { Id = 2 }] });
        var upsert = typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!;
        upsert.Invoke(session, [new SharkordMessage { Id = 13, ChannelId = 7, ParentMessageId = 12 }, false]);
        Assert.Equal(13, Assert.Single(session.GetThreadMessagesSnapshot(12)).Id);
        upsert.Invoke(session, [new SharkordMessage { Id = 13, ChannelId = 7, ParentMessageId = 12, Content = "edited" }, false]);
        Assert.Equal("edited", Assert.Single(session.GetThreadMessagesSnapshot(12)).Content);
        Assert.Empty(session.GetMessagesSnapshot(7));
        typeof(SharkordSession).GetMethod("ApplyTyping", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(session, [new TypingEvent { ChannelId = 7, ParentMessageId = 12, UserId = 2 }]);
        Assert.Empty(session.TypingUsers(7));
        Assert.Equal(2, Assert.Single(session.ThreadTypingUsers(7, 12)).Id);
        typeof(SharkordSession).GetMethod("RemoveMessage", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [13, 7]);
        Assert.Empty(session.GetThreadMessagesSnapshot(12));
    }

    [Fact]
    public async Task SearchValidatesBoundsAndSettingBeforeSending()
    {
        await using var session = new SharkordSession();
        Apply(session, new JoinResult { PublicSettings = new() { EnableSearch = true } });
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() => session.SearchAsync(" x "));
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() => session.SearchAsync(new string('x', 25)));
        Apply(session, new JoinResult { PublicSettings = new() { EnableSearch = false } });
        await Assert.ThrowsAsync<InvalidOperationException>(() => session.SearchAsync("valid"));
    }

    [Fact]
    public async Task DirectMessageCandidatesRespectServerSettingAndDeletedUsers()
    {
        await using var session = new SharkordSession();
        Apply(session, new JoinResult { OwnUserId = 1, PublicSettings = new() { DirectMessagesEnabled = true } });
        Assert.True(session.CanOpenDirectMessage(new() { Id = 2, Name = "member" }));
        Assert.False(session.CanOpenDirectMessage(new() { Id = 1 }));
        Assert.False(session.CanOpenDirectMessage(new() { Id = 2, Banned = true }));
        Assert.False(session.CanOpenDirectMessage(new() { Id = 2, Name = "__deleted_user__" }));
        Apply(session, new JoinResult());
        Assert.False(session.CanOpenDirectMessage(new() { Id = 2 }));
    }
}

