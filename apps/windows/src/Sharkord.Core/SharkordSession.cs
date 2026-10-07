using System.Text.Json.Nodes;

namespace Sharkord.Core;

public enum SessionPhase
{
    Disconnected,
    Connecting,
    Connected,
    Failed
}

/// <summary>
/// Owns one connection to one server: login, handshake, join, every live subscription and
/// the client side state the UI reads. Mirrors <c>SharkordSession</c> on the macOS side.
/// </summary>
public sealed class SharkordSession : IAsyncDisposable
{
    private static readonly TimeSpan[] ReconnectDelays =
    [
        TimeSpan.FromSeconds(1),
        TimeSpan.FromSeconds(2),
        TimeSpan.FromSeconds(4),
        TimeSpan.FromSeconds(8),
        TimeSpan.FromSeconds(8)
    ];

    private readonly Dictionary<int, List<SharkordMessage>> _messagesByChannel = [];
    private readonly Dictionary<int, MessagesCursor> _cursors = [];
    private readonly Dictionary<int, Dictionary<int, DateTime>> _typingByChannel = [];
    private readonly Dictionary<int, int> _replyCounts = [];
    private readonly HashSet<int> _loadedChannels = [];
    private readonly object _gate = new();

    private SharkordHttpClient? _http;
    private TrpcWebSocketClient? _client;
    private string? _token;
    private int _reconnectAttempt;
    private bool _stopping;
    private CancellationTokenSource? _subscriptions;
    private CancellationTokenSource? _voiceSubscriptions;

    /// <summary>Raised whenever observable state changes; the UI re-reads the properties.</summary>
    public event Action? Changed;
    public event Action<VoiceProducerEvent, bool>? VoiceProducerChanged;

    public SessionPhase Phase { get; private set; } = SessionPhase.Disconnected;
    public SharkordServerInfo? ServerInfo { get; private set; }
    public string ServerName { get; private set; } = "";
    public IReadOnlyList<SharkordCategory> Categories { get; private set; } = [];
    public IReadOnlyList<SharkordChannel> Channels { get; private set; } = [];
    public IReadOnlyList<SharkordUser> Users { get; private set; } = [];
    public IReadOnlyList<SharkordRole> Roles { get; private set; } = [];
    public IReadOnlyDictionary<int, ChannelPermissionEntry> ChannelPermissions { get; private set; } =
        new Dictionary<int, ChannelPermissionEntry>();
    public IReadOnlyList<SharkordEmoji> Emojis { get; private set; } = [];
    public IReadOnlyList<DirectMessageConversation> DirectMessages { get; private set; } = [];
    public SharkordSettings? Settings { get; private set; }
    public int OwnUserId { get; private set; }
    public int? SelectedChannelId { get; private set; }
    public string? LastError { get; private set; }
    public int? CurrentVoiceChannelId { get; private set; }

    public IReadOnlyDictionary<int, List<SharkordMessage>> MessagesByChannel => _messagesByChannel;

    public SharkordUser? OwnUser => Users.FirstOrDefault(user => user.Id == OwnUserId);

    public IEnumerable<SharkordChannel> TextChannels => Channels.Where(c => c.IsText && !c.IsDm);

    public IEnumerable<SharkordChannel> DirectMessageChannels =>
        Channels.Where(c => c.IsDm).OrderBy(c => c.CreatedAt);

    public SharkordChannel? Channel(int id) => Channels.FirstOrDefault(c => c.Id == id);

    public bool HasChannelPermission(int channelId, string permission) =>
        ChannelPermissions.TryGetValue(channelId, out var entry) && entry.Allows(permission);

    public bool HasPermission(string permission)
    {
        var ownRoleIds = OwnUser?.RoleIds ?? [];
        return Roles.Any(role => ownRoleIds.Contains(role.Id) && role.Permissions?.Contains(permission) == true);
    }

    public SharkordUser? User(int id) => Users.FirstOrDefault(u => u.Id == id);

    public Uri? PublicFileUrl(SharkordFile file) => _http?.PublicFileUrl(file);

    /// <summary>Reactions of a message grouped into one chip per emoji.</summary>
    public IReadOnlyList<ReactionGroup> ReactionGroups(SharkordMessage message)
    {
        var grouped = new Dictionary<string, ReactionGroup>();

        foreach (var reaction in message.Reactions ?? [])
        {
            if (grouped.TryGetValue(reaction.Emoji, out var existing))
            {
                grouped[reaction.Emoji] = existing with
                {
                    Count = existing.Count + 1,
                    Mine = existing.Mine || reaction.UserId == OwnUserId,
                    File = existing.File ?? reaction.File
                };
            }
            else
            {
                grouped[reaction.Emoji] = new ReactionGroup(
                    reaction.Emoji,
                    1,
                    reaction.UserId == OwnUserId,
                    reaction.File
                );
            }
        }

        return grouped.Values.OrderBy(g => g.Emoji, StringComparer.Ordinal).ToList();
    }

    /// <summary>Users currently typing in a channel, excluding the viewer.</summary>
    public IReadOnlyList<SharkordUser> TypingUsers(int channelId)
    {
        lock (_gate)
        {
            if (!_typingByChannel.TryGetValue(channelId, out var entries))
            {
                return [];
            }

            var now = DateTime.UtcNow;

            return entries
                .Where(e => e.Key != OwnUserId && now - e.Value < ProtocolDefaults.TypingWindow)
                .Select(e => User(e.Key))
                .Where(u => u is not null)
                .Select(u => u!)
                .ToList();
        }
    }

    public int ReplyCount(SharkordMessage message)
        => _replyCounts.TryGetValue(message.Id, out var count) ? count : message.ReplyCount ?? 0;

    public DirectMessageConversation? Conversation(int channelId)
        => DirectMessages.FirstOrDefault(c => c.ChannelId == channelId);

    /// <summary>The other participant of a DM channel, from the viewer's perspective.</summary>
    public SharkordUser? DirectMessagePartner(SharkordChannel channel)
    {
        if (Conversation(channel.Id) is { } conversation)
        {
            return User(conversation.UserId);
        }

        var stripped = channel.Name.Replace("DM - ", "");
        var ids = stripped
            .Split(':')
            .Select(part => int.TryParse(part, out var id) ? id : (int?)null)
            .Where(id => id is not null)
            .Select(id => id!.Value)
            .ToList();

        var partnerId = ids.FirstOrDefault(id => id != OwnUserId, ids.FirstOrDefault());

        return partnerId == 0 ? null : User(partnerId);
    }

    // MARK: - connect

    public async Task ConnectAsync(
        string host,
        string identity,
        string password,
        string? serverPassword = null,
        string? invite = null,
        CancellationToken cancellationToken = default
    )
    {
        if (!TryNormalize(host, out var baseUrl))
        {
            ClientLogStore.Shared.RecordFailure("session.connect.failed", "invalid_server_address");
            SetPhase(SessionPhase.Failed, "Enter a valid server address");
            return;
        }

        ClientLogStore.Shared.RecordInfo("session.connect.started");
        _stopping = false;
        _reconnectAttempt = 0;
        LastError = null;
        SetPhase(SessionPhase.Connecting, null);

        try
        {
            var http = new SharkordHttpClient(baseUrl);
            _http = http;

            ServerInfo = await http.GetInfoAsync(cancellationToken).ConfigureAwait(false);

            var login = await http.LoginAsync(identity, password, invite, cancellationToken)
                .ConfigureAwait(false);

            _token = login.Token;

            await EstablishAsync(baseUrl, login.Token, serverPassword, cancellationToken)
                .ConfigureAwait(false);

            SetPhase(SessionPhase.Connected, null);
            ClientLogStore.Shared.RecordInfo("session.connect.succeeded");
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("session.connect.failed", exception);
            SetPhase(SessionPhase.Failed, Describe(exception));
        }
    }

    private async Task EstablishAsync(
        Uri baseUrl,
        string token,
        string? serverPassword,
        CancellationToken cancellationToken
    )
    {
        var client = new TrpcWebSocketClient(new SharkordHttpClient(baseUrl).WebSocketUrl, token);
        client.Disconnected += exception => HandleUnexpectedDisconnect(exception);

        await client.ConnectAsync(cancellationToken).ConfigureAwait(false);
        _client = client;

        var handshakeNode = await client.QueryAsync("others.handshake", null, cancellationToken)
            .ConfigureAwait(false);
        var handshake = handshakeNode.DeserializeObject<SharkordHandshake>()
            ?? throw new TrpcClientError("PROTOCOL", "Missing handshake");

        var joinInput = new JsonObject { ["handshakeHash"] = handshake.HandshakeHash };

        if (handshake.HasPassword && !string.IsNullOrEmpty(serverPassword))
        {
            joinInput["password"] = serverPassword;
        }

        var joinNode = await client
            .QueryAsync("others.joinServer", joinInput, cancellationToken)
            .ConfigureAwait(false);

        var join = joinNode.DeserializeObject<JoinResult>()
            ?? throw new TrpcClientError("PROTOCOL", "Empty join payload");

        Apply(join);
        StartSubscriptions(client, cancellationToken);
        _reconnectAttempt = 0;

        await LoadDirectMessagesQuietlyAsync().ConfigureAwait(false);
    }

    private void Apply(JoinResult join)
    {
        Categories = join.Categories.OrderBy(c => c.Position).ToList();
        Channels = join.Channels;
        Users = join.Users.OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase).ToList();
        Roles = join.Roles;
        ChannelPermissions = join.ChannelPermissions ?? new Dictionary<int, ChannelPermissionEntry>();
        Emojis = join.Emojis;
        Settings = join.PublicSettings;
        OwnUserId = join.OwnUserId;
        ServerName = join.ServerName;

        if (SelectedChannelId is null)
        {
            var first = TextChannels.FirstOrDefault() ?? DirectMessageChannels.FirstOrDefault();

            if (first is not null)
            {
                SelectedChannelId = first.Id;
            }
        }

        Notify();
    }

    // MARK: - subscriptions

    private void StartSubscriptions(TrpcWebSocketClient client, CancellationToken cancellationToken)
    {
        _subscriptions?.Cancel();
        _subscriptions = new CancellationTokenSource();
        var token = _subscriptions.Token;

        Subscribe(client, "messages.onNew", token, value =>
        {
            var message = value.DeserializeObject<SharkordMessage>();

            if (message is not null)
            {
                Upsert(message, markUnread: message.UserId != OwnUserId);
            }
        });

        Subscribe(client, "messages.onUpdate", token, value =>
        {
            var message = value.DeserializeObject<SharkordMessage>();

            if (message is not null)
            {
                Upsert(message, markUnread: false);
            }
        });

        Subscribe(client, "messages.onDelete", token, value =>
        {
            var channelId = value["channelId"]?.AsInt();
            var messageId = value["messageId"]?.AsInt();

            if (channelId is not null && messageId is not null)
            {
                RemoveMessage(messageId.Value, channelId.Value);
            }
        });

        Subscribe(client, "messages.onTyping", token, value =>
        {
            var typing = value.DeserializeObject<TypingEvent>();

            if (typing is not null)
            {
                lock (_gate)
                {
                    if (!_typingByChannel.TryGetValue(typing.ChannelId, out var entries))
                    {
                        entries = [];
                        _typingByChannel[typing.ChannelId] = entries;
                    }

                    entries[typing.UserId] = DateTime.UtcNow;
                }

                Notify();
            }
        });

        Subscribe(client, "messages.onThreadReplyCountUpdate", token, value =>
        {
            var update = value.DeserializeObject<ReplyCountUpdate>();

            if (update is not null)
            {
                _replyCounts[update.MessageId] = update.ReplyCount;
                Notify();
            }
        });

        Subscribe(client, "users.onJoin", token, value =>
        {
            if (value.DeserializeObject<SharkordUser>() is { } user)
            {
                UpsertUser(user, online: true);
            }
        });

        Subscribe(client, "users.onLeave", token, value =>
        {
            var userId = value.AsInt() ?? value["id"]?.AsInt();

            if (userId is { } id)
            {
                SetStatus(id, "offline");
            }
        });

        Subscribe(client, "users.onUpdate", token, value =>
        {
            if (value.DeserializeObject<SharkordUser>() is { } user)
            {
                UpsertUser(user, online: null);
            }
        });

        Subscribe(client, "users.onCreate", token, value =>
        {
            if (value.DeserializeObject<SharkordUser>() is { } user)
            {
                UpsertUser(user, online: user.Status == "online");
            }
        });

        Subscribe(client, "users.onDelete", token, value =>
        {
            var userId = value.AsInt() ?? value["id"]?.AsInt();

            if (userId is { } id)
            {
                Users = Users.Where(u => u.Id != id).ToList();
                Notify();
            }
        });

        Subscribe(client, "channels.onCreate", token, value => UpsertChannel(value));
        Subscribe(client, "channels.onUpdate", token, value => UpsertChannel(value));

        Subscribe(client, "channels.onDelete", token, value =>
        {
            if (value.AsInt() is { } channelId)
            {
                RemoveChannel(channelId);
            }
        });

        Subscribe(client, "channels.onReadStateUpdate", token, value =>
        {
            var update = value.DeserializeObject<ReadStateUpdate>();

            if (update is not null)
            {
                SetUnread(update.ChannelId, update.Count);
            }
        });

        Subscribe(client, "channels.onReadStateDelta", token, value =>
        {
            var delta = value.DeserializeObject<ReadStateDelta>();

            if (delta is not null && delta.ChannelId != SelectedChannelId)
            {
                ApplyUnreadDelta(delta.ChannelId, delta.Delta);
            }
        });

        Subscribe(client, "categories.onCreate", token, value => UpsertCategory(value));
        Subscribe(client, "categories.onUpdate", token, value => UpsertCategory(value));

        Subscribe(client, "categories.onDelete", token, value =>
        {
            if (value.AsInt() is { } categoryId)
            {
                Categories = Categories.Where(c => c.Id != categoryId).ToList();
                Notify();
            }
        });

        Subscribe(client, "emojis.onCreate", token, value => UpsertEmoji(value));
        Subscribe(client, "emojis.onUpdate", token, value => UpsertEmoji(value));

        Subscribe(client, "emojis.onDelete", token, value =>
        {
            if (value.AsInt() is { } emojiId)
            {
                Emojis = Emojis.Where(e => e.Id != emojiId).ToList();
                Notify();
            }
        });

        Subscribe(client, "roles.onCreate", token, value => UpsertRole(value));
        Subscribe(client, "roles.onUpdate", token, value => UpsertRole(value));

        Subscribe(client, "roles.onDelete", token, value =>
        {
            if (value.AsInt() is { } roleId)
            {
                Roles = Roles.Where(r => r.Id != roleId).ToList();
                Notify();
            }
        });

        Subscribe(client, "others.onServerSettingsUpdate", token, value =>
        {
            if (value.DeserializeObject<SharkordSettings>() is { } settings)
            {
                Settings = settings;
                Notify();
            }
        });

        Subscribe(client, "dms.onConversationOpen", token, ignored => _ = LoadDirectMessagesQuietlyAsync());
    }

    private void Subscribe(
        TrpcWebSocketClient client,
        string path,
        CancellationToken cancellationToken,
        Action<JsonNode> handler
    )
    {
        _ = Task.Run(async () =>
        {
            try
            {
                await foreach (var value in client.SubscribeAsync(path, null, cancellationToken)
                                   .ConfigureAwait(false))
                {
                    handler(value);
                }
            }
            catch (OperationCanceledException)
            {
                // expected on disconnect
            }
            catch
            {
                // the transport surfaces disconnects through the disconnect handler
            }
        }, cancellationToken);
    }

    // MARK: - state mutators

    private void Upsert(SharkordMessage message, bool markUnread)
    {
        lock (_gate)
        {
            if (!_messagesByChannel.TryGetValue(message.ChannelId, out var list))
            {
                list = [];
                _messagesByChannel[message.ChannelId] = list;
            }

            var index = list.FindIndex(m => m.Id == message.Id);

            if (index >= 0)
            {
                list[index] = message;
            }
            else if (message.ParentMessageId is null)
            {
                list.Add(message);
                list.Sort((a, b) => a.CreatedAt.CompareTo(b.CreatedAt));
            }
            else
            {
                return;
            }
        }

        if (markUnread && message.ChannelId != SelectedChannelId)
        {
            ApplyUnreadDelta(message.ChannelId, 1);
        }

        Notify();
    }

    private void RemoveMessage(int messageId, int channelId)
    {
        lock (_gate)
        {
            if (_messagesByChannel.TryGetValue(channelId, out var list))
            {
                list.RemoveAll(m => m.Id == messageId);
            }
        }

        Notify();
    }

    private void UpsertUser(SharkordUser user, bool? online)
    {
        var updated = user;

        if (online is not null)
        {
            updated = user with { Status = online.Value ? "online" : "offline" };
        }

        var list = Users.ToList();
        var index = list.FindIndex(u => u.Id == user.Id);

        if (index >= 0)
        {
            list[index] = updated;
        }
        else if (online == true)
        {
            list.Add(updated);
            list.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
        }

        Users = list;
        Notify();
    }

    private void SetStatus(int userId, string status)
    {
        Users = Users
            .Select(u => u.Id == userId ? u with { Status = status } : u)
            .ToList();

        Notify();
    }

    private void UpsertChannel(JsonNode value)
    {
        var channel = value.DeserializeObject<SharkordChannel>();

        if (channel is null)
        {
            return;
        }

        var list = Channels.ToList();
        var index = list.FindIndex(c => c.Id == channel.Id);

        if (index >= 0)
        {
            list[index] = channel;
        }
        else
        {
            list.Add(channel);
        }

        Channels = list;
        Notify();
    }

    private void RemoveChannel(int channelId)
    {
        Channels = Channels.Where(c => c.Id != channelId).ToList();

        lock (_gate)
        {
            _messagesByChannel.Remove(channelId);
        }

        if (SelectedChannelId == channelId)
        {
            SelectedChannelId = (TextChannels.FirstOrDefault() ?? DirectMessageChannels.FirstOrDefault())?.Id;
        }

        Notify();
    }

    private void UpsertCategory(JsonNode value)
    {
        var category = value.DeserializeObject<SharkordCategory>();

        if (category is null)
        {
            return;
        }

        var list = Categories.ToList();
        var index = list.FindIndex(c => c.Id == category.Id);

        if (index >= 0)
        {
            list[index] = category;
        }
        else
        {
            list.Add(category);
        }

        Categories = list.OrderBy(c => c.Position).ToList();
        Notify();
    }

    private void UpsertEmoji(JsonNode value)
    {
        var emoji = value.DeserializeObject<SharkordEmoji>();

        if (emoji is null)
        {
            return;
        }

        var list = Emojis.ToList();
        var index = list.FindIndex(e => e.Id == emoji.Id);

        if (index >= 0)
        {
            list[index] = emoji;
        }
        else
        {
            list.Add(emoji);
        }

        Emojis = list;
        Notify();
    }

    private void UpsertRole(JsonNode value)
    {
        var role = value.DeserializeObject<SharkordRole>();

        if (role is null)
        {
            return;
        }

        var list = Roles.ToList();
        var index = list.FindIndex(r => r.Id == role.Id);

        if (index >= 0)
        {
            list[index] = role;
        }
        else
        {
            list.Add(role);
        }

        Roles = list;
        Notify();
    }

    private void ApplyUnreadDelta(int channelId, int delta)
    {
        lock (_gate)
        {
            var current = _unreadByChannel.GetValueOrDefault(channelId);
            _unreadByChannel[channelId] = Math.Max(0, current + delta);
        }

        Notify();
    }

    private void SetUnread(int channelId, int count)
    {
        lock (_gate)
        {
            _unreadByChannel[channelId] = count;
        }

        Notify();
    }

    private readonly Dictionary<int, int> _unreadByChannel = [];

    public int UnreadCount(int channelId) => _unreadByChannel.GetValueOrDefault(channelId);

    // MARK: - channel selection + history

    public async Task SelectChannelAsync(int channelId, CancellationToken cancellationToken = default)
    {
        SelectedChannelId = channelId;
        if (Channel(channelId)?.IsVoice == true)
        {
            Notify();
            return;
        }

        SetUnread(channelId, 0);
        Notify();

        if (!_loadedChannels.Add(channelId))
        {
            MarkAsRead(channelId);
            return;
        }

        try
        {
            await LoadAsync(channelId, null, cancellationToken).ConfigureAwait(false);
            MarkAsRead(channelId);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("session.channel_load.failed", exception);
            LastError = Describe(exception);
            _loadedChannels.Remove(channelId);
        }
    }

    public async Task<JsonNode?> JoinVoiceAsync(int channelId, CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var input = new JsonObject
        {
            ["channelId"] = channelId,
            ["state"] = new JsonObject { ["micMuted"] = true, ["soundMuted"] = false }
        };
        var result = await client.MutationAsync("voice.join", input, cancellationToken).ConfigureAwait(false);

        CurrentVoiceChannelId = channelId;
        StartVoiceProducerSubscriptions(client, channelId);
        Notify();
        return result;
    }

    public async Task LeaveVoiceAsync(CancellationToken cancellationToken = default)
    {
        if (CurrentVoiceChannelId is null)
        {
            return;
        }

        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        await client.MutationAsync("voice.leave", null, cancellationToken).ConfigureAwait(false);
        _voiceSubscriptions?.Cancel();
        _voiceSubscriptions?.Dispose();
        _voiceSubscriptions = null;
        CurrentVoiceChannelId = null;
        Notify();
    }

    public async Task<JsonNode?> CallVoiceMediaProcedureAsync(
        string path,
        JsonNode? input = null,
        CancellationToken cancellationToken = default
    )
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        return path switch
        {
            "voice.createProducerTransport" or
            "voice.connectProducerTransport" or
            "voice.produce" or
            "voice.createConsumerTransport" or
            "voice.connectConsumerTransport" or
            "voice.consume" or
            "voice.updateState" or
            "voice.closeProducer" => await client.MutationAsync(path, input, cancellationToken).ConfigureAwait(false),
            "voice.getProducers" => await client.QueryAsync(path, input, cancellationToken).ConfigureAwait(false),
            _ => throw new TrpcClientError("BAD_REQUEST", "This voice media operation is not available")
        };
    }

    private void StartVoiceProducerSubscriptions(TrpcWebSocketClient client, int channelId)
    {
        _voiceSubscriptions?.Cancel();
        _voiceSubscriptions?.Dispose();
        _voiceSubscriptions = new CancellationTokenSource();
        var cancellationToken = _voiceSubscriptions.Token;

        SubscribeVoiceProducerEvents(client, "voice.onNewProducer", channelId, added: true, cancellationToken);
        SubscribeVoiceProducerEvents(client, "voice.onProducerClosed", channelId, added: false, cancellationToken);
    }

    private void SubscribeVoiceProducerEvents(
        TrpcWebSocketClient client,
        string path,
        int channelId,
        bool added,
        CancellationToken cancellationToken
    )
    {
        _ = Task.Run(async () =>
        {
            try
            {
                await foreach (var value in client.SubscribeAsync(path, null, cancellationToken).ConfigureAwait(false))
                {
                    if (value.DeserializeObject<VoiceProducerEvent>() is { } producer && producer.ChannelId == channelId)
                    {
                        VoiceProducerChanged?.Invoke(producer, added);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // expected when leaving voice or disconnecting
            }
            catch
            {
                // the websocket disconnect callback owns connection recovery
            }
        }, cancellationToken);
    }

    public async Task LoadOlderAsync(int channelId, CancellationToken cancellationToken = default)
    {
        if (!_cursors.TryGetValue(channelId, out var cursor))
        {
            return;
        }

        await LoadAsync(channelId, cursor, cancellationToken).ConfigureAwait(false);
    }

    private async Task LoadAsync(int channelId, MessagesCursor? cursor, CancellationToken cancellationToken)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        var input = new JsonObject
        {
            ["channelId"] = channelId,
            ["limit"] = ProtocolDefaults.MessagesLimit
        };

        if (cursor is not null)
        {
            input["cursor"] = new JsonObject
            {
                ["createdAt"] = cursor.CreatedAt,
                ["id"] = cursor.Id
            };
        }

        var node = await client.QueryAsync("messages.get", input, cancellationToken).ConfigureAwait(false);
        var page = node.DeserializeObject<MessagesPage>() ?? new MessagesPage();

        var ascending = page.Messages.OrderBy(m => m.CreatedAt).ToList();

        lock (_gate)
        {
            if (cursor is null)
            {
                _messagesByChannel[channelId] = ascending;
            }
            else if (ascending.Count > 0)
            {
                var existing = _messagesByChannel.TryGetValue(channelId, out var list) ? list : [];
                var existingIds = existing.Select(m => m.Id).ToHashSet();
                _messagesByChannel[channelId] = ascending.Where(m => !existingIds.Contains(m.Id)).Concat(existing).ToList();
            }
        }

        if (page.NextCursor is not null)
        {
            _cursors[channelId] = page.NextCursor;
        }
        else
        {
            _cursors.Remove(channelId);
        }

        Notify();
    }

    // MARK: - message actions

    public async Task SendMessageAsync(
        int channelId,
        string text,
        int? replyToMessageId = null,
        IReadOnlyList<string>? files = null,
        CancellationToken cancellationToken = default
    )
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var trimmed = text.Trim();

        if (trimmed.Length == 0 && (files is null || files.Count == 0))
        {
            return;
        }

        var fileArray = new JsonArray();

        foreach (var file in files ?? [])
        {
            fileArray.Add(file);
        }

        var input = new JsonObject
        {
            ["content"] = MessageHtml.FromPlainText(trimmed),
            ["channelId"] = channelId,
            ["files"] = fileArray
        };

        if (replyToMessageId is { } replyTo)
        {
            input["replyToMessageId"] = replyTo;
        }

        await client.MutationAsync("messages.send", input, cancellationToken).ConfigureAwait(false);
    }

    public async Task EditMessageAsync(int messageId, string text, CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var trimmed = text.Trim();

        if (trimmed.Length == 0)
        {
            return;
        }

        await client.MutationAsync(
            "messages.edit",
            new JsonObject
            {
                ["messageId"] = messageId,
                ["content"] = MessageHtml.FromPlainText(trimmed)
            },
            cancellationToken
        ).ConfigureAwait(false);
    }

    public Task DeleteMessageAsync(int messageId, CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        return client.MutationAsync(
            "messages.delete",
            new JsonObject { ["messageId"] = messageId },
            cancellationToken
        );
    }

    public Task ToggleReactionAsync(int messageId, string emoji, CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        return client.MutationAsync(
            "messages.toggleReaction",
            new JsonObject { ["messageId"] = messageId, ["emoji"] = emoji },
            cancellationToken
        );
    }

    /// <summary>Fire and forget: a typing signal is not worth surfacing an error for.</summary>
    public void SignalTyping(int channelId)
    {
        var client = _client;

        if (client is null)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await client.MutationAsync(
                    "messages.signalTyping",
                    new JsonObject { ["channelId"] = channelId }
                ).ConfigureAwait(false);
            }
            catch
            {
                // ignored, see summary
            }
        });
    }

    public void MarkAsRead(int channelId)
    {
        SetUnread(channelId, 0);

        var client = _client;

        if (client is null)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await client.MutationAsync(
                    "channels.markAsRead",
                    new JsonObject { ["channelId"] = channelId }
                ).ConfigureAwait(false);
            }
            catch
            {
                // ignored, see SignalTyping
            }
        });
    }

    /// <summary>Uploads one attachment and returns the temp file id `messages.send` expects.</summary>
    public async Task<string> UploadAttachmentAsync(
        byte[] data,
        string fileName,
        string mimeType,
        CancellationToken cancellationToken = default
    )
    {
        var http = _http ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var token = _token ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        var temp = await http.UploadAsync(data, fileName, mimeType, token, cancellationToken)
            .ConfigureAwait(false);

        return temp.Id;
    }

    // MARK: - direct messages

    public async Task LoadDirectMessagesAsync(CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        var node = await client.QueryAsync("dms.get", null, cancellationToken).ConfigureAwait(false);
        DirectMessages = node.DeserializeObject<List<DirectMessageConversation>>() ?? [];

        Notify();
    }

    private async Task LoadDirectMessagesQuietlyAsync()
    {
        try
        {
            await LoadDirectMessagesAsync().ConfigureAwait(false);
        }
        catch
        {
            // the conversation list is non-critical; a failure here must not break the join
        }
    }

    /// <summary>Opens (or reuses) the direct message with <paramref name="userId"/> and selects it.</summary>
    public async Task<int> OpenDirectMessageAsync(int userId, CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new TrpcClientError("DISCONNECTED", "Not connected");

        var node = await client.MutationAsync(
            "dms.open",
            new JsonObject { ["userId"] = userId },
            cancellationToken
        ).ConfigureAwait(false);

        var result = node.DeserializeObject<OpenDirectMessageResult>()
            ?? throw new TrpcClientError("PROTOCOL", "Empty DM payload");

        await SelectChannelAsync(result.ChannelId, cancellationToken).ConfigureAwait(false);

        return result.ChannelId;
    }

    // MARK: - disconnect + reconnect

    public async Task DisconnectAsync()
    {
        _stopping = true;
        _subscriptions?.Cancel();
        _voiceSubscriptions?.Cancel();
        _voiceSubscriptions?.Dispose();
        _voiceSubscriptions = null;

        var client = _client;
        _client = null;

        Reset();
        SetPhase(SessionPhase.Disconnected, null);

        if (client is not null)
        {
            await client.DisposeAsync().ConfigureAwait(false);
        }
    }

    private void Reset()
    {
        ServerInfo = null;
        ServerName = "";
        Categories = [];
        Channels = [];
        Users = [];
        Roles = [];
        ChannelPermissions = new Dictionary<int, ChannelPermissionEntry>();
        Emojis = [];
        DirectMessages = [];
        Settings = null;
        OwnUserId = 0;
        SelectedChannelId = null;
        CurrentVoiceChannelId = null;

        lock (_gate)
        {
            _messagesByChannel.Clear();
            _cursors.Clear();
            _typingByChannel.Clear();
            _replyCounts.Clear();
            _loadedChannels.Clear();
            _unreadByChannel.Clear();
        }
    }

    private void HandleUnexpectedDisconnect(Exception? exception)
    {
        if (_stopping || Phase is not (SessionPhase.Connected or SessionPhase.Connecting))
        {
            return;
        }

        if (exception is null)
        {
            ClientLogStore.Shared.RecordFailure("session.disconnected", "connection_closed");
        }
        else
        {
            ClientLogStore.Shared.RecordError("session.disconnected", exception);
        }

        if (_http is null || _token is null || _reconnectAttempt >= ReconnectDelays.Length)
        {
            SetPhase(SessionPhase.Failed, exception is null ? "Connection lost" : Describe(exception));
            return;
        }

        SetPhase(SessionPhase.Connecting, null);

        var attempt = _reconnectAttempt++;
        var baseUrl = _http.BaseUrl;
        var token = _token;

        _ = Task.Run(async () =>
        {
            await Task.Delay(ReconnectDelays[Math.Min(attempt, ReconnectDelays.Length - 1)])
                .ConfigureAwait(false);

            if (_stopping)
            {
                return;
            }

            try
            {
                await EstablishAsync(baseUrl, token, null, CancellationToken.None).ConfigureAwait(false);
                SetPhase(SessionPhase.Connected, null);
            }
            catch (Exception reconnectError)
            {
                HandleUnexpectedDisconnect(reconnectError);
            }
        });
    }

    private static bool TryNormalize(string host, out Uri baseUrl)
    {
        baseUrl = null!;
        var trimmed = host.Trim();

        if (trimmed.Length == 0)
        {
            return false;
        }

        var withScheme = trimmed.Contains("://", StringComparison.Ordinal) ? trimmed : $"http://{trimmed}";

        if (!Uri.TryCreate(withScheme, UriKind.Absolute, out var uri))
        {
            return false;
        }

        if (uri.Scheme is not ("http" or "https") || uri.Host.Length == 0)
        {
            return false;
        }

        baseUrl = uri;

        return true;
    }

    private static string Describe(Exception? exception) => exception switch
    {
        null => "Unknown error",
        TrpcClientError trpc => trpc.Message,
        SharkordHttpError http => http.Message,
        _ => exception.Message
    };

    private void SetPhase(SessionPhase phase, string? error)
    {
        Phase = phase;
        LastError = error;
        Notify();
    }

    private void Notify() => Changed?.Invoke();

    public ValueTask DisposeAsync() => new(DisconnectAsync());
}
