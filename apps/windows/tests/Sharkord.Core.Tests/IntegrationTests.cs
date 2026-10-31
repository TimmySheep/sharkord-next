using System.Net.WebSockets;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;
using Xunit.Abstractions;

namespace Sharkord.Core.Tests;

[CollectionDefinition("live-server", DisableParallelization = true)]
public sealed class LiveServerCollection;

[Collection("live-server")]
public sealed class IntegrationTests(ITestOutputHelper output)
{
    [Fact]
    public async Task LoginJoinSendAndReceive()
    {
        var settings = LiveSettings.Load();
        if (settings is null)
        {
            output.WriteLine("GATED: no live host/credentials configured.");
            return;
        }
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(90));
        var ct = deadline.Token;
        await using var writer = await LiveConnection.OpenAsync(settings, false, ct);
        await using var peer = await LiveConnection.OpenAsync(settings, true, ct);
        Assert.NotEqual(writer.Join.OwnUserId, peer.Join.OwnUserId);
        Assert.Equal(writer.Join.ServerId, peer.Join.ServerId);
        output.WriteLine("PASS: HTTPS login, handshake and join for two owned accounts.");
        // registration assigns a random display name until the welcome profile is saved.
        await writer.Client.MutationAsync("users.update", new JsonObject
        {
            ["name"] = settings.Identity,
            ["profileColor"] = writer.Join.Users.Single(user => user.Id == writer.Join.OwnUserId).ProfileColor
        }, ct);
        await peer.Client.MutationAsync("users.update", new JsonObject
        {
            ["name"] = "Cove acceptance peer",
            ["profileColor"] = peer.Join.Users.Single(user => user.Id == peer.Join.OwnUserId).ProfileColor
        }, ct);
        output.WriteLine("PASS: owned test-account display profiles saved through the normal update route.");
        var channelId = (await writer.Client.MutationAsync("dms.open", new JsonObject { ["userId"] = peer.Join.OwnUserId }, ct))!.AsObject().GetInt("channelId")!.Value;
        var peerDm = await peer.Client.MutationAsync("dms.open", new JsonObject { ["userId"] = writer.Join.OwnUserId }, ct);
        Assert.Equal(channelId, peerDm!["channelId"].AsInt());
        var owned = new List<int>();
        var marker = $"cove-it-{Guid.NewGuid():N}";
        try
        {
            await using var received = new LiveEvents(peer.Client, "messages.onNew", ct);
            await using var updated = new LiveEvents(peer.Client, "messages.onUpdate", ct);
            await using var deleted = new LiveEvents(peer.Client, "messages.onDelete", ct);
            await using var typing = new LiveEvents(peer.Client, "messages.onTyping", ct);
            await using var read = new LiveEvents(writer.Client, "channels.onReadStateUpdate", ct);
            await Task.Delay(300, ct);
            var root = await SendAsync(writer, channelId, marker, owned, ct);
            var delivered = await received.NextAsync(value => value.AsObject().GetInt("id") == root);
            Assert.Equal(writer.Join.OwnUserId, delivered.AsObject().GetInt("userId"));
            Assert.Contains(marker, (await GetAsync(writer, root, ct)).Content);
            output.WriteLine("PASS: owned DM open, send, peer live receive and persisted fetch.");

            await writer.Client.MutationAsync("messages.edit", new JsonObject { ["messageId"] = root, ["content"] = $"<p>{marker}-edited</p>" }, ct);
            await updated.NextAsync(value => value.AsObject().GetInt("id") == root && value.AsObject().GetString("content")!.Contains("-edited"));
            Assert.Contains("-edited", (await GetAsync(writer, root, ct)).Content);
            await writer.Client.MutationAsync("messages.toggleReaction", new JsonObject { ["messageId"] = root, ["emoji"] = "thumbsup" }, ct);
            Assert.Contains((await GetAsync(writer, root, ct)).Reactions!, reaction => reaction.UserId == writer.Join.OwnUserId && reaction.Emoji == "thumbsup");
            output.WriteLine("PASS: edit live update and persisted shortcode reaction.");

            var reply = await SendAsync(writer, channelId, marker + "-reply", owned, ct, replyTo: root);
            Assert.Equal(root, (await GetAsync(writer, reply, ct)).ReplyToMessageId);
            var thread = await SendAsync(writer, channelId, marker + "-thread", owned, ct, parent: root);
            var page = (await writer.Client.QueryAsync("messages.getThread", new JsonObject { ["parentMessageId"] = root, ["limit"] = 1 }, ct)).DeserializeObject<MessagesPage>()!;
            Assert.Contains(page.Messages, message => message.Id == thread && message.ParentMessageId == root);
            await writer.Client.MutationAsync("messages.signalTyping", new JsonObject { ["channelId"] = channelId, ["parentMessageId"] = root }, ct);
            await typing.NextAsync(value => value.AsObject().GetInt("channelId") == channelId && value.AsObject().GetInt("parentMessageId") == root && value.AsObject().GetInt("userId") == writer.Join.OwnUserId);
            await writer.Client.MutationAsync("messages.signalTyping", new JsonObject { ["channelId"] = channelId }, ct);
            await typing.NextAsync(value => value.AsObject().GetInt("channelId") == channelId && value.AsObject().GetInt("parentMessageId") is null && value.AsObject().GetInt("userId") == writer.Join.OwnUserId);
            await writer.Client.MutationAsync("channels.markAsRead", new JsonObject { ["channelId"] = channelId }, ct);
            await read.NextAsync(value => value.AsObject().GetInt("channelId") == channelId && value.AsObject().GetInt("count") == 0);
            output.WriteLine("PASS: inline reply, thread fetch, thread typing and own read-state event.");

            var bytes = Encoding.UTF8.GetBytes(marker + "\nowned acceptance attachment\n");
            var temporary = await writer.Http.UploadAsync(bytes, "cove-acceptance-附件.txt", "text/plain", writer.Token, ct);
            var attachment = await SendAsync(writer, channelId, marker + "-file", owned, ct, file: temporary.Id);
            var saved = Assert.Single((await GetAsync(writer, attachment, ct)).Files!);
            Assert.Equal("cove-acceptance-附件.txt", saved.OriginalName);
            using var download = new HttpClient();
            Assert.Equal(bytes, await download.GetByteArrayAsync(writer.Http.PublicFileUrl(saved), ct));
            output.WriteLine("PASS: raw upload, Unicode filename and /public byte comparison.");

            await DeleteAsync(writer, root, channelId, ct);
            owned.Remove(root);
            owned.Remove(thread);
            await deleted.NextAsync(value => value.AsObject().GetInt("messageId") == root && value.AsObject().GetInt("channelId") == channelId);
            var after = (await writer.Client.QueryAsync("messages.get", new JsonObject { ["channelId"] = channelId, ["limit"] = 50 }, ct)).DeserializeObject<MessagesPage>()!;
            Assert.DoesNotContain(after.Messages, message => message.Id == root);
            output.WriteLine("PASS: owned delete event and persisted absence.");
        }
        finally { await CleanupAsync(writer, owned, channelId); }
    }

    [Fact]
    public async Task EditReactDeleteAndDirectMessage()
    {
        var settings = LiveSettings.Load();
        if (settings is null)
        {
            output.WriteLine("GATED: no live host/credentials configured.");
            return;
        }
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(90));
        var ct = deadline.Token;
        await using var peer = await LiveConnection.OpenAsync(settings, true, ct);
        await using var session = new SharkordSession();
        await session.ConnectAsync(settings.Host.AbsoluteUri, settings.Identity, settings.Password, cancellationToken: ct);
        Assert.True(session.Phase == SessionPhase.Connected, session.LastError);
        var channelId = (await session.CallMutationAsync("dms.open", new JsonObject { ["userId"] = peer.Join.OwnUserId }, ct))!["channelId"].AsInt()!.Value;
        var owned = new List<int>();
        var marker = $"cove-resync-{Guid.NewGuid():N}";
        try
        {
            var edited = await SendAsync(peer, channelId, marker + "-before", owned, ct);
            var deleted = await SendAsync(peer, channelId, marker + "-delete", owned, ct);
            await session.SelectChannelAsync(channelId, ct);
            Assert.Contains(session.GetMessagesSnapshot(channelId), message => message.Id == edited);
            // abort only this test's socket so the normal transport loop performs recovery.
            var transport = (TrpcWebSocketClient)typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(session)!;
            var socket = (ClientWebSocket)typeof(TrpcWebSocketClient).GetField("_socket", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(transport)!;
            socket.Abort();
            await WaitUntilAsync(() => session.Phase != SessionPhase.Connected, ct);
            await peer.Client.MutationAsync("messages.edit", new JsonObject { ["messageId"] = edited, ["content"] = $"<p>{marker}-offline-edit</p>" }, ct);
            await DeleteAsync(peer, deleted, channelId, ct);
            owned.Remove(deleted);
            var missed = await SendAsync(peer, channelId, marker + "-offline-new", owned, ct);
            await WaitUntilAsync(() => session.Phase == SessionPhase.Connected && session.GetMessagesSnapshot(channelId).Any(message => message.Id == missed), ct);
            var resynced = session.GetMessagesSnapshot(channelId);
            Assert.Contains(resynced, message => message.Id == edited && message.Content!.Contains("offline-edit"));
            Assert.DoesNotContain(resynced, message => message.Id == deleted);
            Assert.Equal(channelId, session.SelectedChannelId);
            Assert.Contains(session.DirectMessages, dm => dm.ChannelId == channelId);
            output.WriteLine("PASS: real socket abort, automatic reconnect, selected DM and missed new/edit/delete resync.");
        }
        finally
        {
            await session.DisconnectAsync();
            await CleanupAsync(peer, owned, channelId);
        }
    }

    private static async Task<int> SendAsync(LiveConnection connection, int channel, string text, List<int> owned,
        CancellationToken ct, int? replyTo = null, int? parent = null, string? file = null)
    {
        var input = new JsonObject { ["channelId"] = channel, ["content"] = $"<p>{text}</p>", ["files"] = file is null ? new JsonArray() : new JsonArray(file) };
        if (replyTo is { } reply) input["replyToMessageId"] = reply;
        if (parent is { } parentId) input["parentMessageId"] = parentId;
        var id = (await connection.Client.MutationAsync("messages.send", input, ct)).AsInt()!.Value;
        owned.Add(id);
        return id;
    }

    private static async Task<SharkordMessage> GetAsync(LiveConnection connection, int id, CancellationToken ct) =>
        (await connection.Client.QueryAsync("messages.getOne", new JsonObject { ["messageId"] = id }, ct)).DeserializeObject<SharkordMessage>()!;

    private static async Task DeleteAsync(LiveConnection connection, int id, int channel, CancellationToken ct)
    {
        var message = await GetAsync(connection, id, ct);
        Assert.Equal(connection.Join.OwnUserId, message.UserId);
        Assert.Equal(channel, message.ChannelId);
        await connection.Client.MutationAsync("messages.delete", new JsonObject { ["messageId"] = id }, ct);
    }

    private async Task CleanupAsync(LiveConnection connection, List<int> owned, int channel)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        foreach (var id in owned.AsEnumerable().Reverse())
        {
            try { await DeleteAsync(connection, id, channel, deadline.Token); }
            catch (TrpcClientError error) when (error.Message == "Message not found")
            {
                // an owned parent deletion may have cascaded to its owned replies.
            }
        }
        output.WriteLine("PASS: cleanup checked owner/channel for ids created by this run only.");
    }

    private static async Task WaitUntilAsync(Func<bool> condition, CancellationToken ct)
    {
        while (!condition()) await Task.Delay(50, ct);
    }
}

internal sealed record LiveSettings(Uri Host, string Identity, string Password, string PeerIdentity, string PeerPassword)
{
    public static LiveSettings? Load()
    {
        var host = Environment.GetEnvironmentVariable("SHARKORD_IT_HOST");
        if (string.IsNullOrWhiteSpace(host)) return null;
        var path = Environment.GetEnvironmentVariable("SHARKORD_IT_CREDS") ?? "C:/Users/YY/codex-task/server-creds.txt";
        if (!File.Exists(path)) return null;
        var value = JsonNode.Parse(File.ReadAllText(path))!;
        var target = new Uri(host.Contains("://") ? host : $"http://{host}");
        if (target != new Uri(Required(value, "host"))) throw new InvalidOperationException("Live target differs from credentials origin.");
        return new(target, Required(value, "identity"), Required(value, "password"), Required(value, "peerIdentity"), Required(value, "peerPassword"));
    }

    private static string Required(JsonNode value, string key) => value.AsObject().GetString(key) is { Length: > 0 } text
        ? text : throw new InvalidOperationException($"Credentials file is missing {key}.");
}

internal sealed class LiveConnection(SharkordHttpClient http, TrpcWebSocketClient client, string token, JoinResult join) : IAsyncDisposable
{
    public SharkordHttpClient Http { get; } = http;
    public TrpcWebSocketClient Client { get; } = client;
    public string Token { get; } = token;
    public JoinResult Join { get; } = join;

    public static async Task<LiveConnection> OpenAsync(LiveSettings settings, bool peer, CancellationToken ct)
    {
        var http = new SharkordHttpClient(settings.Host);
        var info = await http.GetInfoAsync(ct);
        var login = await http.LoginAsync(peer ? settings.PeerIdentity : settings.Identity, peer ? settings.PeerPassword : settings.Password, cancellationToken: ct);
        Assert.False(string.IsNullOrEmpty(login.Token));
        var client = new TrpcWebSocketClient(http.WebSocketUrl, login.Token);
        try
        {
            await client.ConnectAsync(ct);
            var handshake = (await client.QueryAsync("others.handshake", cancellationToken: ct)).DeserializeObject<SharkordHandshake>()!;
            Assert.False(handshake.HasPassword);
            var join = (await client.QueryAsync("others.joinServer", new JsonObject { ["handshakeHash"] = handshake.HandshakeHash }, ct)).DeserializeObject<JoinResult>()!;
            Assert.Equal(info.ServerId, join.ServerId);
            Assert.True(join.OwnUserId > 0);
            return new(http, client, login.Token, join);
        }
        catch { await client.DisposeAsync(); throw; }
    }

    public ValueTask DisposeAsync() => Client.DisposeAsync();
}

internal sealed class LiveEvents : IAsyncDisposable
{
    private readonly CancellationTokenSource _stop;
    private readonly System.Threading.Channels.Channel<JsonNode> _events = System.Threading.Channels.Channel.CreateUnbounded<JsonNode>();
    private readonly Task _pump;

    public LiveEvents(TrpcWebSocketClient client, string path, CancellationToken ct)
    {
        _stop = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _pump = PumpAsync(client, path);
    }

    private async Task PumpAsync(TrpcWebSocketClient client, string path)
    {
        try
        {
            await foreach (var value in client.SubscribeAsync(path, cancellationToken: _stop.Token)) await _events.Writer.WriteAsync(value, _stop.Token);
            _events.Writer.TryComplete();
        }
        catch (OperationCanceledException) { _events.Writer.TryComplete(); }
        catch (Exception error) { _events.Writer.TryComplete(error); }
    }

    public async Task<JsonNode> NextAsync(Func<JsonNode, bool> matches)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_stop.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(15));
        await foreach (var value in _events.Reader.ReadAllAsync(deadline.Token)) if (matches(value)) return value;
        throw new InvalidOperationException("Expected live event was not received.");
    }

    public async ValueTask DisposeAsync()
    {
        await _stop.CancelAsync();
        await _pump;
        _stop.Dispose();
    }
}
