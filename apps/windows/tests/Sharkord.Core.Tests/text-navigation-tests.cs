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
            Assert.Equal("messages.getOne", request["params"]!["path"]!.GetValue<string>());
            await Respond(request, "{\"id\":12,\"channelId\":7}");
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
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

    [Fact]
    public async Task JoinConversationSnapshotReplacesStateAndHidesClosedConversations()
    {
        await using var session = new SharkordSession();
        Apply(session, JsonNode.Parse("{\"channels\":[{\"id\":7,\"isDm\":true},{\"id\":8,\"isDm\":true}],\"directMessages\":[{\"channelId\":7,\"userId\":2},{\"channelId\":8,\"userId\":3,\"closedAt\":100}]}").DeserializeObject<JoinResult>()!);
        Assert.Equal(7, Assert.Single(session.DirectMessageChannels).Id);
        Assert.Equal(2, session.Conversation(7)?.UserId);
        Apply(session, JsonNode.Parse("{\"directMessages\":[]}").DeserializeObject<JoinResult>()!);
        Assert.Empty(session.DirectMessages);
    }

    [Fact]
    public async Task ThreadSendPreservesParentAndReplyIdentifiers()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var send = session.SendMessageAsync(7, "reply text", 13, cancellationToken: token, parentMessageId: 12);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("mutation", request["method"]!.GetValue<string>());
            Assert.Equal("messages.send", request["params"]!["path"]!.GetValue<string>());
            var input = request["params"]!["input"]!;
            Assert.Equal(7, input["channelId"]!.GetValue<int>());
            Assert.Equal(12, input["parentMessageId"]!.GetValue<int>());
            Assert.Equal(13, input["replyToMessageId"]!.GetValue<int>());
            Assert.Equal("<p>reply text</p>", input["content"]!.GetValue<string>());
            await WebSocketConformanceTests.SendAsync(server, $"{{\"id\":{request["id"]},\"result\":{{\"data\":null}}}}", token);
            await send;
        });
    }

    [Fact]
    public async Task OlderJumpResponseCannotOverrideReturnToPresent()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var jump = session.JumpToMessageAsync(7, 12, token);
            var lookup = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            await WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{lookup["id"]},\"result\":{{\"data\":{{\"id\":12,\"channelId\":7}}}}}}", token);
            var old = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            var present = session.ReturnToPresentAsync(7, token);
            var current = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            await Respond(current, 99);
            await present;
            await Respond(old, 12);
            Assert.Null(await jump);
            Assert.Equal(99, Assert.Single(session.GetMessagesSnapshot(7)).Id);
            Task Respond(JsonNode request, int id) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{{\"messages\":[{{\"id\":{id},\"channelId\":7}}]}}}}}}", token);
        });
    }

    [Fact]
    public async Task LegacyConversationQueryRemainsAvailableWithoutJoinSnapshot()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            Apply(session, new JoinResult { Channels = [new() { Id = 7, IsDm = true }] });
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var load = session.LoadDirectMessagesAsync(token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("dms.get", request["params"]!["path"]!.GetValue<string>());
            await WebSocketConformanceTests.SendAsync(server, $"{{\"id\":{request["id"]},\"result\":{{\"data\":[{{\"channelId\":7,\"userId\":2}}]}}}}", token);
            await load;
            Assert.Equal(2, Assert.Single(session.DirectMessages).UserId);
            Assert.Equal(7, Assert.Single(session.DirectMessageChannels).Id);
        });
    }

    [Fact]
    public async Task ConversationUpdatesCloseAndReopenSnapshotRows()
    {
        await using var session = new SharkordSession();
        Apply(session, JsonNode.Parse("{\"channels\":[{\"id\":7,\"isDm\":true}],\"directMessages\":[{\"channelId\":7,\"userId\":2}]}").DeserializeObject<JoinResult>()!);
        var update = typeof(SharkordSession).GetMethod("ApplyConversationUpdate", BindingFlags.Instance | BindingFlags.NonPublic)!;
        update.Invoke(session, [JsonNode.Parse("{\"channelId\":7,\"userId\":2,\"closedAt\":100}")!]);
        Assert.Empty(session.DirectMessageChannels);
        update.Invoke(session, [JsonNode.Parse("{\"channelId\":7,\"userId\":2,\"closedAt\":null}")!]);
        Assert.Equal(7, Assert.Single(session.DirectMessageChannels).Id);
    }

    [Fact]
    public async Task PermissionRevocationDropsPrivateHistoryAndSelection()
    {
        await using var session = new SharkordSession();
        Apply(session, new JoinResult { Channels = [new() { Id = 7, IsPrivate = true }], ChannelPermissions = new() { [7] = new() { Permissions = new() { ["VIEW_CHANNEL"] = true } } } });
        typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(session, [new SharkordMessage { Id = 1, ChannelId = 7 }, false]);
        typeof(SharkordSession).GetMethod("ApplyChannelPermissions", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [new JsonObject()]);
        Assert.Empty(session.GetMessagesSnapshot(7));
        Assert.Null(session.SelectedChannelId);
        Assert.False(session.CanViewChannel(session.Channel(7)!));
    }

    [Theory]
    [InlineData(null)]
    [InlineData(12)]
    public async Task TypingOmitsAbsentThreadAndPreservesThreadIdentifier(int? parentId)
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            session.SignalTyping(7, parentId);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            await WebSocketConformanceTests.SendAsync(server, $"{{\"id\":{request["id"]},\"result\":{{\"data\":null}}}}", token);
            Assert.Equal("messages.signalTyping", request["params"]!["path"]!.GetValue<string>());
            var input = request["params"]!["input"]!.AsObject();
            Assert.Equal(7, input["channelId"]!.GetValue<int>());
            Assert.Equal(parentId is not null, input.ContainsKey("parentMessageId"));
            if (parentId is not null) { Assert.Equal(parentId, input["parentMessageId"]!.GetValue<int>()); }
        });
    }

    [Fact]
    public async Task ThreadReplyDeletionInvalidatesRenderedRows()
    {
        await using var session = new SharkordSession();
        typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(session, [new SharkordMessage { Id = 13, ChannelId = 7, ParentMessageId = 12 }, false]);
        var revision = session.ThreadRevision;
        typeof(SharkordSession).GetMethod("RemoveMessage", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [13, 7]);
        Assert.Empty(session.GetThreadMessagesSnapshot(12));
        Assert.True(session.ThreadRevision > revision);
    }

    [Fact]
    public async Task PermissionRefreshPreservesAnAccessiblePendingHistoryPage()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 7 }] });
            var selection = session.SelectChannelAsync(7, token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            typeof(SharkordSession).GetMethod("ApplyChannelPermissions", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [new JsonObject()]);
            await WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{{\"messages\":[{{\"id\":12,\"channelId\":7}}]}}}}}}", token);
            await selection;
            Assert.Equal(12, Assert.Single(session.GetMessagesSnapshot(7)).Id);
        });
    }

    [Fact]
    public async Task OlderThreadResponseCannotReplaceNewerPages()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var older = session.LoadThreadAsync(12, cancellationToken: token);
            var oldRequest = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            var current = session.LoadThreadAsync(12, cancellationToken: token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            await Respond(request, "{\"messages\":[{\"id\":13,\"channelId\":7,\"parentMessageId\":12,\"createdAt\":100}],\"nextCursor\":{\"id\":13,\"createdAt\":100}}");
            await current;
            current = session.LoadThreadAsync(12, more: true, cancellationToken: token);
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            await Respond(request, "{\"messages\":[{\"id\":14,\"channelId\":7,\"parentMessageId\":12,\"createdAt\":200}]}");
            await current;
            await Respond(oldRequest, "{\"messages\":[{\"id\":13,\"channelId\":7,\"parentMessageId\":12,\"createdAt\":100}],\"nextCursor\":{\"id\":13,\"createdAt\":100}}");
            await older;
            Assert.Equal(new[] { 13, 14 }, session.GetThreadMessagesSnapshot(12).Select(message => message.Id));
            Assert.False(session.HasMoreThreadMessages(12));
            Task Respond(JsonNode request, string data) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{data}}}}}", token);
        });
    }

    [Fact]
    public async Task JumpNotifiesSelectionBeforeWaitingForTargetHistory()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 8 }, new() { Id = 7 }] });
            int? visibleSelection = 8;
            session.Changed += () => visibleSelection = session.SelectedChannelId;
            var jump = session.JumpToMessageAsync(7, 12, token);
            await WebSocketConformanceTests.ReceiveAsync(server, token);
            Assert.Equal(7, session.SelectedChannelId);
            Assert.Equal(session.SelectedChannelId, visibleSelection);
            server.Abort();
            await Assert.ThrowsAnyAsync<Exception>(() => jump);
        });
    }

    [Fact]
    public async Task StaleTargetLookupCannotOverrideLaterChannelSelection()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 7 }, new() { Id = 8, Type = "VOICE" }] });
            var jump = session.JumpToMessageAsync(7, 12, token);
            var lookup = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.getOne", lookup["params"]!["path"]!.GetValue<string>());
            await session.SelectChannelAsync(8, token);
            await WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{lookup["id"]},\"result\":{{\"data\":{{\"id\":12,\"channelId\":7}}}}}}", token);
            Assert.Null(await jump);
            Assert.Equal(8, session.SelectedChannelId);
            Assert.Empty(session.GetMessagesSnapshot(7));
        });
    }

    [Fact]
    public async Task VoiceChannelTextSelectionLoadsMessagesAndSurvivesRejoin()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            var join = new JoinResult { Channels = [new() { Id = 7, Type = "VOICE" }] };
            Apply(session, join);
            await session.SelectChannelAsync(7, token);
            Assert.False(session.IsVoiceTextSelected);
            var selectText = session.SelectChannelAsync(7, token, includeVoiceText: true);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.get", request["params"]!["path"]!.GetValue<string>());
            await WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{{\"messages\":[{{\"id\":12,\"channelId\":7}}]}}}}}}", token);
            await selectText;
            Assert.True(session.IsVoiceTextSelected);
            Assert.Equal(12, Assert.Single(session.GetMessagesSnapshot(7)).Id);
            Apply(session, join);
            Assert.True(session.IsVoiceTextSelected);
            Assert.Empty(session.GetMessagesSnapshot(7));
            await session.SelectChannelAsync(7, token);
            Assert.False(session.IsVoiceTextSelected);
        });
    }

    [Fact]
    public async Task RejoinWithoutAccessibleChannelsClearsSelection()
    {
        await using var session = new SharkordSession();
        Apply(session, new JoinResult { Channels = [new() { Id = 7 }] });
        Apply(session, new JoinResult());
        Assert.Null(session.SelectedChannelId);
    }

    [Fact]
    public async Task ThreadTargetJumpLoadsItsRootWindow()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 7, Type = "VOICE" }] });
            var jump = session.JumpToMessageAsync(7, 13, token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.getOne", request["params"]!["path"]!.GetValue<string>());
            await Respond(request, "{\"id\":13,\"channelId\":7,\"parentMessageId\":12}");
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal(12, request["params"]!["input"]!["targetMessageId"]!.GetValue<int>());
            await Respond(request, "{\"messages\":[{\"id\":12,\"channelId\":7}],\"hasNewer\":true}");
            Assert.Equal(13, (await jump)?.Id);
            Assert.True(session.IsVoiceTextSelected);
            Assert.True(session.HasNewerMessages(7));
            Task Respond(JsonNode request, string data) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{data}}}}}", token);
        });
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task DeletedThreadCannotReturnFromPendingPage(bool removeChannel)
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            Apply(session, new JoinResult { Channels = [new() { Id = 7 }] });
            var upsert = typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!;
            upsert.Invoke(session, [new SharkordMessage { Id = 12, ChannelId = 7 }, false]);
            upsert.Invoke(session, [new SharkordMessage { Id = 13, ChannelId = 7, ParentMessageId = 12 }, false]);
            var load = session.LoadThreadAsync(12, cancellationToken: token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            var method = removeChannel ? "RemoveChannel" : "RemoveMessage";
            object[] arguments = removeChannel ? [7] : [12, 7];
            typeof(SharkordSession).GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, arguments);
            Assert.Empty(session.GetMessagesSnapshot(7));
            Assert.Empty(session.GetThreadMessagesSnapshot(12));
            await WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{request["id"]},\"result\":{{\"data\":{{\"messages\":[{{\"id\":13,\"channelId\":7,\"parentMessageId\":12}}]}}}}}}", token);
            await load;
            Assert.Empty(session.GetThreadMessagesSnapshot(12));
        });
    }
}

