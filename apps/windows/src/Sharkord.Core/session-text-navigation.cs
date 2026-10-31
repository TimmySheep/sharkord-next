using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed partial class SharkordSession
{
    private readonly Dictionary<int, List<SharkordMessage>> _messagesByThread = [];
    private readonly Dictionary<int, MessagesCursor> _threadCursors = [];
    private readonly Dictionary<(int ChannelId, int ParentId), Dictionary<int, DateTime>> _threadTyping = [];
    private readonly HashSet<int> _hasNewer = [];
    private readonly Dictionary<int, long> _historyRequests = [];
    private readonly Dictionary<int, long> _threadRequests = [];
    private readonly Dictionary<int, Dictionary<int, SharkordMessage?>> _threadLiveChanges = [];
    private long _historyGeneration;
    private long _navigationRequest;

    private void InvalidateHistory()
    {
        _historyGeneration++;
        _navigationRequest++;
        foreach (var channelId in _messagesByChannel.Keys)
        {
            _messageRevisions[channelId] = ++_nextMessageRevision;
        }
        _messagesByChannel.Clear();
        _cursors.Clear();
        _typingByChannel.Clear();
        _replyCounts.Clear();
        _loadedChannels.Clear();
        _messagesByThread.Clear();
        _threadCursors.Clear();
        _threadTyping.Clear();
        _hasNewer.Clear();
        _historyRequests.Clear();
        _threadRequests.Clear();
        _threadLiveChanges.Clear();
    }

    private void InvalidateChannelHistory(int channelId)
    {
        var parentIds = _messagesByChannel.GetValueOrDefault(channelId)?.Select(message => message.Id).ToHashSet() ?? [];
        parentIds.UnionWith(_messagesByThread.Where(entry => entry.Value.Any(message => message.ChannelId == channelId)).Select(entry => entry.Key));
        _messagesByChannel.Remove(channelId);
        _cursors.Remove(channelId);
        _loadedChannels.Remove(channelId);
        _hasNewer.Remove(channelId);
        _typingByChannel.Remove(channelId);
        _historyRequests[channelId] = _historyRequests.GetValueOrDefault(channelId) + 1;
        _messageRevisions[channelId] = ++_nextMessageRevision;
        foreach (var parentId in parentIds)
        {
            _messagesByThread.Remove(parentId);
            _threadCursors.Remove(parentId);
            _replyCounts.Remove(parentId);
            _threadRequests[parentId] = _threadRequests.GetValueOrDefault(parentId) + 1;
        }
        foreach (var key in _threadTyping.Keys.Where(key => key.ChannelId == channelId).ToArray()) { _threadTyping.Remove(key); }
    }

    public bool CanViewChannel(SharkordChannel channel) =>
        OwnUser?.RoleIds?.Contains(1) == true || !channel.IsPrivate ||
        channel.Id == CurrentVoiceChannelId || HasChannelPermission(channel.Id, "VIEW_CHANNEL");

    public bool CanOpenDirectMessage(SharkordUser user) =>
        Settings?.DirectMessagesEnabled == true && user.Id != OwnUserId &&
        !user.Banned && user.Name != "__deleted_user__";

    public bool CanManageMessage(SharkordMessage message) =>
        message.UserId == OwnUserId || HasPermission("MANAGE_MESSAGES");

    public long HistoryGeneration { get { lock (_gate) { return _historyGeneration; } } }

    public long ThreadRevision { get { lock (_gate) { return _nextMessageRevision; } } }

    public bool IsVoiceTextSelected { get; private set; }

    public bool HasNewerMessages(int channelId)
    {
        lock (_gate) { return _hasNewer.Contains(channelId); }
    }

    public async Task<SharkordMessage?> JumpToMessageAsync(int channelId, int messageId, CancellationToken cancellationToken = default)
    {
        long request;
        long generation;
        lock (_gate)
        {
            request = ++_navigationRequest;
            generation = _historyGeneration;
            SelectedChannelId = channelId;
            IsVoiceTextSelected = Channel(channelId)?.IsVoice == true;
        }
        Notify();
        var node = await CallQueryAsync("messages.getOne", new JsonObject { ["messageId"] = messageId }, cancellationToken).ConfigureAwait(false);
        lock (_gate)
        {
            if (request != _navigationRequest || generation != _historyGeneration || SelectedChannelId != channelId) { return null; }
        }
        var target = node.DeserializeObject<SharkordMessage>() ?? throw new TrpcClientError("NOT_FOUND", I18n.L10n.T("originalMessageUnavailable"));
        if (target.ChannelId != channelId) { throw new TrpcClientError("NOT_FOUND", I18n.L10n.T("originalMessageUnavailable")); }
        if (!await LoadAsync(channelId, null, cancellationToken, target.ParentMessageId ?? target.Id).ConfigureAwait(false)) { return null; }
        lock (_gate)
        {
            if (request != _navigationRequest || generation != _historyGeneration || SelectedChannelId != channelId) { return null; }
            _loadedChannels.Add(channelId);
        }
        return target;
    }

    public async Task ReturnToPresentAsync(int channelId, CancellationToken cancellationToken = default)
    {
        lock (_gate) { _navigationRequest++; }
        await LoadAsync(channelId, null, cancellationToken).ConfigureAwait(false);
    }

    public IReadOnlyList<SharkordMessage> GetThreadMessagesSnapshot(int parentMessageId)
    {
        lock (_gate)
        {
            return _messagesByThread.TryGetValue(parentMessageId, out var messages) ? messages.ToArray() : [];
        }
    }

    public bool HasMoreThreadMessages(int parentMessageId)
    {
        lock (_gate) { return _threadCursors.ContainsKey(parentMessageId); }
    }

    public async Task LoadThreadAsync(int parentMessageId, bool more = false, CancellationToken cancellationToken = default)
    {
        var input = new JsonObject { ["parentMessageId"] = parentMessageId, ["limit"] = ProtocolDefaults.MessagesLimit };
        long generation;
        long request;
        var changes = new Dictionary<int, SharkordMessage?>();
        lock (_gate)
        {
            generation = _historyGeneration;
            if (more)
            {
                if (!_threadCursors.TryGetValue(parentMessageId, out var cursor)) { return; }
                input["cursor"] = new JsonObject { ["id"] = cursor.Id, ["createdAt"] = cursor.CreatedAt };
            }
            request = _threadRequests.GetValueOrDefault(parentMessageId) + 1;
            _threadRequests[parentMessageId] = request;
            _threadLiveChanges[parentMessageId] = changes;
        }
        try
        {
            var result = await CallQueryAsync("messages.getThread", input, cancellationToken).ConfigureAwait(false);
            var page = result.DeserializeObject<MessagesPage>() ?? new();
            lock (_gate)
            {
                if (generation != _historyGeneration || request != _threadRequests.GetValueOrDefault(parentMessageId)) { return; }
                var merged = more && _messagesByThread.TryGetValue(parentMessageId, out var existing)
                    ? existing.ToDictionary(message => message.Id) : [];
                foreach (var message in page.Messages) { merged.TryAdd(message.Id, message); }
                // live events are newer than the outstanding page snapshot, including unseen deletions.
                foreach (var (id, message) in changes)
                {
                    if (message is null) { merged.Remove(id); }
                    else { merged[id] = message; }
                }
                _messagesByThread[parentMessageId] = merged.Values.OrderBy(message => message, MessageOrder).ToList();
                _nextMessageRevision++;
                if (page.NextCursor is { } next) { _threadCursors[parentMessageId] = next; }
                else { _threadCursors.Remove(parentMessageId); }
            }
            Notify();
        }
        finally
        {
            lock (_gate)
            {
                if (ReferenceEquals(_threadLiveChanges.GetValueOrDefault(parentMessageId), changes)) { _threadLiveChanges.Remove(parentMessageId); }
            }
        }
    }

    public Task<JsonNode?> SearchAsync(string query, CancellationToken cancellationToken = default)
    {
        var trimmed = query.Trim();
        if (trimmed.Length is < 2 or > 24) { throw new ArgumentOutOfRangeException(nameof(query)); }
        if (Settings?.EnableSearch != true) { throw new InvalidOperationException("Search is disabled on this server"); }
        return CallQueryAsync("messages.search", new JsonObject { ["query"] = trimmed }, cancellationToken);
    }

    public async Task<IReadOnlyList<SharkordMessage>> GetPinnedMessagesAsync(int channelId, CancellationToken cancellationToken = default)
    {
        var node = await CallQueryAsync("messages.getPinned", new JsonObject { ["channelId"] = channelId }, cancellationToken).ConfigureAwait(false);
        return node.DeserializeObject<List<SharkordMessage>>() ?? [];
    }

    public Task<JsonNode?> TogglePinAsync(int messageId, CancellationToken cancellationToken = default) =>
        CallMutationAsync("messages.togglePin", new JsonObject { ["messageId"] = messageId }, cancellationToken);

    private void ApplyTyping(TypingEvent typing)
    {
        lock (_gate)
        {
            Dictionary<int, DateTime>? entries;
            if (typing.ParentMessageId is { } parentId)
            {
                var key = (typing.ChannelId, parentId);
                if (!_threadTyping.TryGetValue(key, out entries)) { _threadTyping[key] = entries = []; }
            }
            else if (!_typingByChannel.TryGetValue(typing.ChannelId, out entries))
            {
                _typingByChannel[typing.ChannelId] = entries = [];
            }
            entries[typing.UserId] = DateTime.UtcNow;
        }
        Notify();
    }

    public IReadOnlyList<SharkordUser> ThreadTypingUsers(int channelId, int parentMessageId)
    {
        lock (_gate)
        {
            if (!_threadTyping.TryGetValue((channelId, parentMessageId), out var entries)) { return []; }
            return entries.Where(entry => entry.Key != OwnUserId && DateTime.UtcNow - entry.Value < ProtocolDefaults.TypingWindow)
                .Select(entry => User(entry.Key)).OfType<SharkordUser>().ToArray();
        }
    }

    private void ApplyConversationUpdate(JsonNode value)
    {
        var conversation = value.DeserializeObject<DirectMessageConversation>();
        if (conversation is null) { return; }
        DirectMessages = DirectMessages.Where(existing => existing.ChannelId != conversation.ChannelId).Append(conversation).ToArray();
        Notify();
    }

    private void ApplyChannelPermissions(JsonNode value)
    {
        ChannelPermissions = value.DeserializeObject<Dictionary<int, ChannelPermissionEntry>>() ?? [];
        lock (_gate)
        {
            foreach (var channel in Channels.Where(channel => !CanViewChannel(channel)))
            {
                InvalidateChannelHistory(channel.Id);
                if (SelectedChannelId == channel.Id) { SelectedChannelId = null; }
            }
        }
        Notify();
    }
}
