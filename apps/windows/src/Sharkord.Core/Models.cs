using System.Text.Json.Serialization;

namespace Sharkord.Core;

/// <summary>
/// Decodable models for the subset of the protocol the client renders. JSON field names
/// are matched case-insensitively, so only the few keys whose JSON name is not the
/// PascalCase of the property need an explicit attribute.
/// </summary>
public sealed class SharkordFile
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public string OriginalName { get; init; } = "";
    public string Md5 { get; init; } = "";
    public long Size { get; init; }
    public string MimeType { get; init; } = "";

    [JsonPropertyName("extension")]
    public string FileExtension { get; init; } = "";

    public long CreatedAt { get; init; }
    public long? UpdatedAt { get; init; }

    [JsonPropertyName("_accessToken")]
    public string? AccessToken { get; init; }

    [JsonPropertyName("_accessTokenExpiresAt")]
    public long? AccessTokenExpiresAt { get; init; }
}

public sealed class SharkordCategory
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public int Position { get; init; }
    public long CreatedAt { get; init; }
    public long? UpdatedAt { get; init; }
}

public sealed class SharkordChannel
{
    public int Id { get; init; }
    public string Type { get; init; } = "TEXT";
    public string Name { get; init; } = "";
    public string? Topic { get; init; }

    [JsonPropertyName("private")]
    public bool IsPrivate { get; init; }

    public bool IsDm { get; init; }
    public int Position { get; init; }
    public int? CategoryId { get; init; }
    public long CreatedAt { get; init; }
    public long? UpdatedAt { get; init; }

    [JsonIgnore]
    public bool IsVoice => string.Equals(Type, "VOICE", StringComparison.OrdinalIgnoreCase);

    [JsonIgnore]
    public bool IsText => !IsVoice;
}

public sealed record SharkordUser
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public string ProfileColor { get; init; } = "#262626";
    public string? Bio { get; init; }
    public SharkordFile? Avatar { get; init; }
    public int? AvatarId { get; init; }
    public SharkordFile? Banner { get; init; }
    public int? BannerId { get; init; }
    public bool Banned { get; init; }
    public long CreatedAt { get; init; }
    public string? Status { get; init; }
    public List<int>? RoleIds { get; init; }
}

public sealed class SharkordRole
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public string Color { get; init; } = "#ffffff";
    public bool IsPersistent { get; init; }
    public bool IsDefault { get; init; }
    public List<string>? Permissions { get; init; }
}

public sealed class SharkordMessageReaction
{
    public int MessageId { get; init; }
    public int UserId { get; init; }
    public string Emoji { get; init; } = "";
    public int? FileId { get; init; }
    public SharkordFile? File { get; init; }
}

public sealed class SharkordReplyPreview
{
    public int Id { get; init; }
    public string? Content { get; init; }
    public int? UserId { get; init; }
    public string? PluginId { get; init; }
}

public sealed class SharkordMessage
{
    public int Id { get; init; }
    public string? Content { get; init; }
    public int? UserId { get; init; }
    public string? PluginId { get; init; }
    public int ChannelId { get; init; }
    public int? ParentMessageId { get; init; }
    public int? ReplyToMessageId { get; init; }
    public bool? Editable { get; init; }
    public long CreatedAt { get; init; }
    public long? UpdatedAt { get; init; }
    public bool? Pinned { get; init; }
    public long? EditedAt { get; init; }
    public List<SharkordFile>? Files { get; init; }
    public List<SharkordMessageReaction>? Reactions { get; init; }
    public int? ReplyCount { get; init; }
    public SharkordReplyPreview? ReplyTo { get; init; }
}

public sealed class SharkordSettings
{
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public string ServerId { get; init; } = "";
    public bool? StorageUploadEnabled { get; init; }
    public bool? DirectMessagesEnabled { get; init; }
    public long? StorageQuota { get; init; }
    public long? StorageUploadMaxFileSize { get; init; }
    public bool? StorageFileSharingInDirectMessages { get; init; }
    public int? StorageMaxFilesPerMessage { get; init; }
    public bool? EnablePlugins { get; init; }
    public bool? EnableSearch { get; init; }
    public bool? StorageSignedUrlsEnabled { get; init; }
    public long? WebRtcMaxBitrate { get; init; }
}

public sealed class SharkordServerInfo
{
    public string ServerId { get; init; } = "";
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public SharkordFile? Logo { get; init; }
    public bool AllowNewUsers { get; init; }
    public bool? OidcEnabled { get; init; }
    public bool? OidcDisableLocalLogin { get; init; }
    public string? Version { get; init; }
}

public sealed class SharkordLoginResult
{
    public bool? Success { get; init; }
    public string Token { get; init; } = "";
}

public sealed class SharkordHandshake
{
    public string HandshakeHash { get; init; } = "";
    public bool HasPassword { get; init; }
}

public sealed class MessagesCursor
{
    public long CreatedAt { get; init; }
    public int Id { get; init; }
}

public sealed class MessagesPage
{
    public List<SharkordMessage> Messages { get; init; } = [];
    public MessagesCursor? NextCursor { get; init; }
    public bool? HasNewer { get; init; }
}

/// <summary>The `others.joinServer` payload; only the fields the client uses are declared.</summary>
public sealed class JoinResult
{
    public List<SharkordCategory> Categories { get; init; } = [];
    public List<SharkordChannel> Channels { get; init; } = [];
    public List<SharkordUser> Users { get; init; } = [];
    public List<SharkordRole> Roles { get; init; } = [];
    public Dictionary<int, ChannelPermissionEntry>? ChannelPermissions { get; init; }
    public List<SharkordEmoji> Emojis { get; init; } = [];
    public string ServerId { get; init; } = "";
    public string ServerName { get; init; } = "";
    public int OwnUserId { get; init; }
    public bool? OwnUserPasswordSet { get; init; }
    public SharkordSettings PublicSettings { get; init; } = new();
    public Dictionary<string, long>? ReadStates { get; init; }
    public bool? ShowWelcomeDialog { get; init; }
}

public sealed class ChannelPermissionEntry
{
    public int ChannelId { get; init; }
    public Dictionary<string, bool> Permissions { get; init; } = new(StringComparer.OrdinalIgnoreCase);

    public bool Allows(string permission) => Permissions.TryGetValue(permission, out var allowed) && allowed;
}

public sealed class SharkordTempFile
{
    public string Id { get; init; } = "";
    public string OriginalName { get; init; } = "";
    public long Size { get; init; }
    public string Md5 { get; init; } = "";
    public string Path { get; init; } = "";

    [JsonPropertyName("extension")]
    public string FileExtension { get; init; } = "";

    public int? UserId { get; init; }
}

public sealed class SharkordPublicUser
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public string? ProfileColor { get; init; }
    public SharkordFile? Avatar { get; init; }
    public SharkordFile? Banner { get; init; }
}

public sealed class SharkordEmoji
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public int FileId { get; init; }
    public int? UserId { get; init; }
    public long CreatedAt { get; init; }
    public SharkordFile? File { get; init; }
    public SharkordPublicUser? User { get; init; }
}

public sealed class DirectMessageConversation
{
    public int ChannelId { get; init; }
    public int UserId { get; init; }
    public int UnreadCount { get; init; }
    public long LastMessageAt { get; init; }
}

public sealed class ReadStateUpdate
{
    public int ChannelId { get; init; }
    public int Count { get; init; }
}

public sealed class ReadStateDelta
{
    public int ChannelId { get; init; }
    public int Delta { get; init; }
}

public sealed class TypingEvent
{
    public int ChannelId { get; init; }
    public int UserId { get; init; }
    public int? ParentMessageId { get; init; }
}

public sealed class VoiceProducerEvent
{
    public int ChannelId { get; init; }
    public int RemoteId { get; init; }
    public string Kind { get; init; } = "";
}

public sealed class ReplyCountUpdate
{
    public int MessageId { get; init; }
    public int ChannelId { get; init; }
    public int ReplyCount { get; init; }
}

public sealed class OpenDirectMessageResult
{
    public int ChannelId { get; init; }
}

/// <summary>One reaction chip: an emoji with its count and whether the viewer reacted.</summary>
public sealed record ReactionGroup(string Emoji, int Count, bool Mine, SharkordFile? File);

public static class ProtocolDefaults
{
    public const int MessagesLimit = 100;
    public const int MessageMaxLength = 10_000;
    public static readonly TimeSpan TypingWindow = TimeSpan.FromSeconds(6);
}
