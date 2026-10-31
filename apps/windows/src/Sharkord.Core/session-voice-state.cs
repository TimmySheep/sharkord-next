using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed record VoiceUserState(bool MicMuted = true, bool SoundMuted = false, bool WebcamEnabled = false, bool SharingScreen = false);
public sealed record VoiceParticipant(int UserId, VoiceUserState State);
public sealed record VoiceChannelState(Dictionary<int, VoiceUserState> Users);
public sealed record ExternalVoiceStream(string Title, string? Key, string? PluginId, string? AvatarUrl, JsonObject? Tracks);

public sealed partial class SharkordSession
{
    private Dictionary<int, Dictionary<int, VoiceUserState>> _voiceUsers = [];
    private Dictionary<int, Dictionary<int, ExternalVoiceStream>> _externalStreams = [];
    public event Action<int, int>? VoiceMoveRequested;
    public event Action<int, int, string>? VoiceReactionReceived;

    public IReadOnlyList<VoiceParticipant> GetVoiceUsers(int channelId)
    {
        lock (_gate)
        {
            return _voiceUsers.TryGetValue(channelId, out var users)
                ? users.Select(entry => new VoiceParticipant(entry.Key, entry.Value)).OrderBy(user => user.UserId).ToArray() : [];
        }
    }

    public IReadOnlyList<KeyValuePair<int, ExternalVoiceStream>> GetExternalStreams(int channelId)
    {
        lock (_gate) { return _externalStreams.TryGetValue(channelId, out var streams) ? streams.ToArray() : []; }
    }

    private void ApplyVoiceSnapshot(JoinResult joined)
    {
        lock (_gate)
        {
            _voiceUsers = joined.VoiceMap?.ToDictionary(entry => entry.Key, entry => new Dictionary<int, VoiceUserState>(entry.Value.Users)) ?? [];
            _externalStreams = joined.ExternalStreamsMap?.ToDictionary(entry => entry.Key, entry => new Dictionary<int, ExternalVoiceStream>(entry.Value)) ?? [];
        }
    }

    private void SubscribeVoiceState(TrpcWebSocketClient client, CancellationToken token)
    {
        Subscribe(client, "voice.onJoin", token, ApplyVoiceUser);
        Subscribe(client, "voice.onUpdateState", token, ApplyVoiceUser);
        Subscribe(client, "voice.onLeave", token, ApplyVoiceLeave);
        Subscribe(client, "voice.onAddExternalStream", token, ApplyExternalStream);
        Subscribe(client, "voice.onUpdateExternalStream", token, ApplyExternalStream);
        Subscribe(client, "voice.onRemoveExternalStream", token, value =>
        {
            if (value is not JsonObject node || node.GetInt("channelId") is not { } channelId || node.GetInt("streamId") is not { } id) { return; }
            lock (_gate) { if (_externalStreams.TryGetValue(channelId, out var streams)) { streams.Remove(id); } }
            Notify();
        });
        Subscribe(client, "voice.onReaction", token, value =>
        {
            if (value is JsonObject node && node.GetInt("channelId") is { } channelId && node.GetInt("userId") is { } id && node.GetString("emoji") is { } emoji)
            {
                VoiceReactionReceived?.Invoke(channelId, id, emoji);
            }
        });
        Subscribe(client, "voice.onMoved", token, value =>
        {
            if (value is JsonObject node && node.GetInt("fromChannelId") is { } from && node.GetInt("channelId") is { } target && CurrentVoiceChannelId == from)
            {
                VoiceMoveRequested?.Invoke(from, target);
            }
        });
    }

    private void ApplyVoiceUser(JsonNode value)
    {
        if (value is not JsonObject node || node.GetInt("channelId") is not { } channelId || node.GetInt("userId") is not { } id || node["state"].DeserializeObject<VoiceUserState>() is not { } state) { return; }
        lock (_gate)
        {
            if (!_voiceUsers.TryGetValue(channelId, out var users)) { _voiceUsers[channelId] = users = []; }
            users[id] = state;
        }
        Notify();
    }

    private void ApplyVoiceLeave(JsonNode value)
    {
        if (value is not JsonObject node || node.GetInt("channelId") is not { } channelId || node.GetInt("userId") is not { } id) { return; }
        lock (_gate) { if (_voiceUsers.TryGetValue(channelId, out var users)) { users.Remove(id); } }
        Notify();
    }

    private void ApplyExternalStream(JsonNode value)
    {
        if (value is not JsonObject node || node.GetInt("channelId") is not { } channelId || node.GetInt("streamId") is not { } id || node["stream"].DeserializeObject<ExternalVoiceStream>() is not { } stream) { return; }
        lock (_gate)
        {
            if (!_externalStreams.TryGetValue(channelId, out var streams)) { _externalStreams[channelId] = streams = []; }
            streams[id] = stream;
        }
        Notify();
    }
}
