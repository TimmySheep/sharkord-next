import Foundation

/// Decodable models for the protocol the client speaks. Field names match the server's
/// camelCase JSON. Fields the UI cannot do without are required, everything else is
/// optional so a server that grows a record does not break decoding.
public enum ChannelType: String, Codable, Sendable {
    case text = "TEXT"
    case voice = "VOICE"
}

public enum UserStatus: String, Codable, Sendable {
    case online
    case idle
    case offline
}

public enum Permission: String, Codable, Sendable, CaseIterable {
    case sendMessages = "SEND_MESSAGES"
    case reactToMessages = "REACT_TO_MESSAGES"
    case pinMessages = "PIN_MESSAGES"
    case uploadFiles = "UPLOAD_FILES"
    case joinVoiceChannels = "JOIN_VOICE_CHANNELS"
    case shareScreen = "SHARE_SCREEN"
    case enableWebcam = "ENABLE_WEBCAM"
    case sendVoiceReaction = "SEND_VOICE_REACTION"
    case manageChannels = "MANAGE_CHANNELS"
    case manageChannelPermissions = "MANAGE_CHANNEL_PERMISSIONS"
    case manageCategories = "MANAGE_CATEGORIES"
    case manageRoles = "MANAGE_ROLES"
    case manageEmojis = "MANAGE_EMOJIS"
    case manageSettings = "MANAGE_SETTINGS"
    case manageUsers = "MANAGE_USERS"
    case moveMembers = "MOVE_MEMBERS"
    case manageMessages = "MANAGE_MESSAGES"
    case manageStorage = "MANAGE_STORAGE"
    case manageInvites = "MANAGE_INVITES"
    case manageUpdates = "MANAGE_UPDATES"
    case managePlugins = "MANAGE_PLUGINS"
    case managePluginPermissions = "MANAGE_PLUGIN_PERMISSIONS"
    case usePlugins = "USE_PLUGINS"
    case viewUserSensitiveData = "VIEW_USER_SENSITIVE_DATA"
}

public enum ChannelPermission: String, Codable, Sendable, CaseIterable {
    case viewChannel = "VIEW_CHANNEL"
    case sendMessages = "SEND_MESSAGES"
    case join = "JOIN"
    case speak = "SPEAK"
    case shareScreen = "SHARE_SCREEN"
    case webcam = "WEBCAM"
}

public enum StreamKind: String, Codable, Sendable {
    case audio
    case video
    case screen
    case screenAudio = "screen_audio"
    case externalVideo = "external_video"
    case externalAudio = "external_audio"
}

public enum ProducibleKind: String, Codable, Sendable {
    case audio
    case video
    case screen
    case screenAudio = "screen_audio"
}

// MARK: - files

public struct SharkordFile: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let originalName: String
    public let md5: String
    public let size: Int
    public let mimeType: String
    public let fileExtension: String
    public let createdAt: Int
    public let updatedAt: Int?
    public let _accessToken: String?
    public let _accessTokenExpiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalName
        case md5
        case size
        case mimeType
        case fileExtension = "extension"
        case createdAt
        case updatedAt
        case _accessToken
        case _accessTokenExpiresAt
    }
}

public struct SharkordTempFile: Codable, Sendable {
    public let id: String
    public let originalName: String
    public let size: Int
    public let md5: String
    public let path: String
    public let fileExtension: String
    public let userId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case originalName
        case size
        case md5
        case path
        case fileExtension = "extension"
        case userId
    }
}

// MARK: - channels and categories

public struct SharkordCategory: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let position: Int
    public let createdAt: Int
    public let updatedAt: Int?
}

public struct SharkordChannel: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let type: ChannelType
    public let name: String
    public let topic: String?
    public let isPrivate: Bool
    public let isDm: Bool
    public let position: Int
    public let categoryId: Int?
    public let createdAt: Int
    public let updatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case topic
        case isPrivate = "private"
        case isDm
        case position
        case categoryId
        case createdAt
        case updatedAt
    }
}

/// `channels.updatePermissions` accepts either a user or a role, never both.
public struct ChannelPermissionUpdate: Codable, Sendable {
    public let channelId: Int
    public let userId: Int?
    public let roleId: Int?
    public let isCreate: Bool?
    public let permissions: [ChannelPermission]?

    public init(
        channelId: Int,
        userId: Int? = nil,
        roleId: Int? = nil,
        isCreate: Bool? = nil,
        permissions: [ChannelPermission]? = nil
    ) {
        self.channelId = channelId
        self.userId = userId
        self.roleId = roleId
        self.isCreate = isCreate
        self.permissions = permissions
    }
}

public struct ChannelRolePermission: Codable, Sendable, Hashable {
    public let channelId: Int
    public let roleId: Int
    public let permission: ChannelPermission
    public let allow: Bool
    public let createdAt: Int
    public let updatedAt: Int?
}

public struct ChannelUserPermission: Codable, Sendable, Hashable {
    public let channelId: Int
    public let userId: Int
    public let permission: ChannelPermission
    public let allow: Bool
    public let createdAt: Int
    public let updatedAt: Int?
}

public struct ChannelPermissionsResult: Codable, Sendable {
    public let rolePermissions: [ChannelRolePermission]
    public let userPermissions: [ChannelUserPermission]
}

/// `Record<channelId, { channelId, permissions: Record<ChannelPermission, boolean> }>`.
public struct ChannelPermissionsMap: Codable, Sendable {
    public let entries: [Int: ChannelPermissionEntry]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entries = try container.decode([String: ChannelPermissionEntry].self)
            .reduce(into: [:]) { result, entry in
                if let key = Int(entry.key) {
                    result[key] = entry.value
                }
            }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries.reduce(into: [String: ChannelPermissionEntry]()) { result, entry in
            result[String(entry.key)] = entry.value
        })
    }

    public init(entries: [Int: ChannelPermissionEntry] = [:]) {
        self.entries = entries
    }

    public subscript(channelId: Int) -> ChannelPermissionEntry? {
        entries[channelId]
    }
}

public struct ChannelPermissionEntry: Codable, Sendable, Hashable {
    public let channelId: Int
    public let permissions: [String: Bool]

    public func allows(_ permission: ChannelPermission) -> Bool {
        permissions[permission.rawValue] ?? false
    }
}

// MARK: - users

public struct SharkordUser: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let profileColor: String
    public let bio: String?
    public let avatar: SharkordFile?
    public let avatarId: Int?
    public let banner: SharkordFile?
    public let bannerId: Int?
    public let banned: Bool
    public let createdAt: Int
    public var status: UserStatus?
    public var roleIds: [Int]?
    public let _identity: String?

    func withStatus(_ status: UserStatus?) -> SharkordUser {
        var copy = self
        copy.status = status

        return copy
    }

    func withRoleIds(_ roleIds: [Int]) -> SharkordUser {
        var copy = self
        copy.roleIds = roleIds

        return copy
    }
}

/// The sender fields the server trims for a public user (`TJoinedPublicUser` without identity).
public struct SharkordPublicUser: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let profileColor: String?
    public let avatar: SharkordFile?
    public let banner: SharkordFile?
}

/// `users.getInfo` / `users.getAll` view: the full row plus relations, with the sensitive
/// columns stripped unless the caller holds `VIEW_USER_SENSITIVE_DATA`.
public struct SharkordAdminUser: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let identity: String?
    public let name: String
    public let avatarId: Int?
    public let bannerId: Int?
    public let bio: String?
    public let banned: Bool
    public let banReason: String?
    public let bannedAt: Int?
    public let profileColor: String?
    public let passwordSet: Bool?
    public let lastLoginAt: Int?
    public let createdAt: Int
    public let updatedAt: Int?
    public let avatar: SharkordFile?
    public let banner: SharkordFile?
    public let roleIds: [Int]?
    public let isOidcUser: Bool?
}

public struct SharkordLogin: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let userId: Int?
    public let ip: String?
    public let location: String?
    public let createdAt: Int
}

public struct UserStorageInfo: Codable, Sendable {
    public let userId: Int
    public let fileCount: Int
    public let usedStorage: Int
    public let quota: Int?
}

public struct UserDetail: Codable, Sendable {
    public let user: SharkordAdminUser
    public let logins: [SharkordLogin]
    public let files: [SharkordFile]
    public let messages: [SharkordMessage]
    public let storage: UserStorageInfo
}

// MARK: - roles

public struct SharkordRole: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let color: String
    public let isPersistent: Bool
    public let isDefault: Bool
    public let permissions: [String]?
    public let storageQuotaOverrideEnabled: Bool?
    public let storageSpaceQuota: Int?
    public let createdAt: Int
    public let updatedAt: Int?

    public func allows(_ permission: Permission) -> Bool {
        permissions?.contains(permission.rawValue) ?? false
    }
}

public struct RoleUpdate: Codable, Sendable {
    public let roleId: Int
    public let name: String
    public let color: String
    public let permissions: [String]
    public let storageQuotaOverrideEnabled: Bool
    public let storageSpaceQuota: Int

    public init(
        roleId: Int,
        name: String,
        color: String,
        permissions: [String],
        storageQuotaOverrideEnabled: Bool,
        storageSpaceQuota: Int
    ) {
        self.roleId = roleId
        self.name = name
        self.color = color
        self.permissions = permissions
        self.storageQuotaOverrideEnabled = storageQuotaOverrideEnabled
        self.storageSpaceQuota = storageSpaceQuota
    }
}

// MARK: - messages

public struct SharkordMessageReaction: Codable, Sendable, Hashable {
    public let messageId: Int
    public let userId: Int?
    public let pluginId: String?
    public let emoji: String
    public let fileId: Int?
    public let file: SharkordFile?
}

public struct SharkordReplyPreview: Codable, Sendable, Hashable {
    public let id: Int
    public let content: String?
    public let userId: Int?
    public let pluginId: String?
}

/// Link previews the web client's `embeds` helper attaches to a message.
public struct MessageMetadata: Codable, Sendable, Hashable {
    public let kind: String
    public let url: String
    public let title: String?
    public let siteName: String?
    public let description: String?
    public let mediaType: String?
    public let images: [String]?
    public let videos: [String]?
    public let favicons: [String]?
}

public struct SharkordMessage: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let content: String?
    public let userId: Int?
    public let pluginId: String?
    public let channelId: Int
    public let parentMessageId: Int?
    public let replyToMessageId: Int?
    public let editable: Bool?
    public let metadata: [MessageMetadata]?
    public let createdAt: Int
    public let updatedAt: Int?
    public let pinned: Bool?
    public let pinnedAt: Int?
    public let pinnedBy: Int?
    public let editedAt: Int?
    public let editedBy: Int?
    public let files: [SharkordFile]?
    public let reactions: [SharkordMessageReaction]?
    public let replyCount: Int?
    public let replyTo: SharkordReplyPreview?
}

/// `messages.search` results: a message with the channel it came from and a plain text
/// snippet, plus a parallel file search.
public struct SearchMessage: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let content: String?
    public let plainContent: String?
    public let userId: Int?
    public let channelId: Int
    public let channelName: String
    public let channelIsDm: Bool
    public let createdAt: Int
    public let files: [SharkordFile]?
}

public struct SearchFile: Codable, Sendable, Hashable {
    public let file: SharkordFile
    public let messageId: Int
    public let channelId: Int
    public let messageContent: String?
    public let messageCreatedAt: Int
    public let channelName: String
    public let channelIsDm: Bool
}

public struct SearchResult: Codable, Sendable {
    public let messages: [SearchMessage]
    public let files: [SearchFile]
    public let truncated: Bool
}

public struct MessagesCursor: Codable, Sendable, Hashable {
    public let createdAt: Int
    public let id: Int
}

public struct MessagesPage: Codable, Sendable {
    public let messages: [SharkordMessage]
    public let nextCursor: MessagesCursor?
    public let hasNewer: Bool?
}

public struct ThreadPage: Codable, Sendable {
    public let messages: [SharkordMessage]
    public let nextCursor: MessagesCursor?
}

// MARK: - invites

public struct SharkordInvite: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let code: String
    public let creatorId: Int
    public let roleId: Int?
    public let maxUses: Int?
    public let uses: Int
    public let expiresAt: Int?
    public let createdAt: Int
    public let creator: SharkordPublicUser?
    public let role: InviteRole?
}

public struct InviteRole: Codable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let color: String
}

public struct InviteCreate: Codable, Sendable {
    public let maxUses: Int?
    public let expiresAt: Int?
    public let code: String?
    public let roleId: Int?

    public init(maxUses: Int? = nil, expiresAt: Int? = nil, code: String? = nil, roleId: Int? = nil) {
        self.maxUses = maxUses
        self.expiresAt = expiresAt
        self.code = code
        self.roleId = roleId
    }
}

// MARK: - emoji

public struct SharkordEmoji: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let fileId: Int
    public let userId: Int?
    public let createdAt: Int
    public let file: SharkordFile?
    public let user: SharkordPublicUser?
}

public struct EmojiCreateEntry: Codable, Sendable {
    public let fileId: String
    public let name: String

    public init(fileId: String, name: String) {
        self.fileId = fileId
        self.name = name
    }
}

// MARK: - voice

public struct VoiceUserState: Codable, Sendable, Hashable {
    public let micMuted: Bool
    public let soundMuted: Bool
    public let webcamEnabled: Bool?
    public let sharingScreen: Bool?

    public init(micMuted: Bool, soundMuted: Bool, webcamEnabled: Bool? = nil, sharingScreen: Bool? = nil) {
        self.micMuted = micMuted
        self.soundMuted = soundMuted
        self.webcamEnabled = webcamEnabled
        self.sharingScreen = sharingScreen
    }
}

/// `Record<channelId, { users: Record<userId, state> }>`.
public struct VoiceMap: Codable, Sendable {
    public let entries: [Int: VoiceChannelUsers]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entries = try container.decode([String: VoiceChannelUsers].self)
            .reduce(into: [:]) { result, entry in
                if let key = Int(entry.key) {
                    result[key] = entry.value
                }
            }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries.reduce(into: [String: VoiceChannelUsers]()) { result, entry in
            result[String(entry.key)] = entry.value
        })
    }

    public init(entries: [Int: VoiceChannelUsers] = [:]) {
        self.entries = entries
    }

    public subscript(channelId: Int) -> VoiceChannelUsers? {
        entries[channelId]
    }
}

public struct VoiceChannelUsers: Codable, Sendable {
    public let users: [String: VoiceUserState]

    public func states() -> [Int: VoiceUserState] {
        users.reduce(into: [:]) { result, entry in
            if let key = Int(entry.key) {
                result[key] = entry.value
            }
        }
    }
}

public struct ExternalStream: Codable, Sendable, Hashable {
    public let title: String
    public let key: String
    public let pluginId: String?
    public let avatarUrl: String?
    public let bannerUrl: String?
    public let tracks: ExternalStreamTracks?
}

public struct ExternalStreamTracks: Codable, Sendable, Hashable {
    public let audio: Bool?
    public let video: Bool?
}

/// `Record<channelId, Record<streamId, TExternalStream>>`.
public struct ExternalStreamsMap: Codable, Sendable {
    public let entries: [Int: [String: ExternalStream]]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: [String: ExternalStream]].self)

        entries = raw.reduce(into: [:]) { result, entry in
            if let key = Int(entry.key) {
                result[key] = entry.value
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries.reduce(into: [String: [String: ExternalStream]]()) { result, entry in
            result[String(entry.key)] = entry.value
        })
    }

    public init(entries: [Int: [String: ExternalStream]] = [:]) {
        self.entries = entries
    }
}

public struct VoiceTransportParams: Codable, Sendable {
    public let id: String
    public let iceParameters: JSONValue?
    public let iceCandidates: JSONValue?
    public let dtlsParameters: JSONValue?
}

public struct RemoteProducerIds: Codable, Sendable {
    public let remoteVideoIds: [Int]
    public let remoteAudioIds: [Int]
    public let remoteScreenIds: [Int]
    public let remoteScreenAudioIds: [Int]
    public let remoteExternalStreamIds: [Int]
}

public struct StreamQualityLayer: Codable, Sendable, Hashable {
    public let spatialLayer: Int
    public let label: String
}

public struct ConsumeResult: Codable, Sendable {
    public let producerId: String
    public let consumerId: String
    public let consumerKind: StreamKind
    public let consumerRtpParameters: JSONValue?
    public let consumerType: String
    public let qualityLayers: [StreamQualityLayer]?
}

public struct VoiceJoinEvent: Codable, Sendable {
    public let channelId: Int
    public let userId: Int
    public let state: VoiceUserState
}

public struct VoiceLeaveEvent: Codable, Sendable {
    public let channelId: Int
    public let userId: Int
}

public struct VoiceMovedEvent: Codable, Sendable {
    public let channelId: Int
    public let fromChannelId: Int
}

public struct VoiceReactionEvent: Codable, Sendable {
    public let channelId: Int
    public let userId: Int
    public let emoji: String
}

public struct VoiceProducerEvent: Codable, Sendable {
    public let channelId: Int
    public let remoteId: Int
    public let kind: StreamKind
}

public struct VoiceExternalStreamEvent: Codable, Sendable {
    public let channelId: Int
    public let streamId: String?
    public let stream: ExternalStream?
}

// MARK: - plugins

public struct PluginInfo: Codable, Sendable, Identifiable, Hashable {
    public var id: String { pluginId }

    public let pluginId: String
    public let enabled: Bool
    public let loadError: String?
    public let sdkVersion: Int
    public let author: String?
    public let description: String?
    public let version: String?
    public let logo: String?
    public let name: String?
    public let homepage: String?
    public let path: String?

    enum CodingKeys: String, CodingKey {
        case pluginId = "id"
        case enabled
        case loadError
        case sdkVersion
        case author
        case description
        case version
        case logo
        case name
        case homepage
        case path
    }
}

public struct PluginMetadata: Codable, Sendable, Hashable {
    public let pluginId: String
    public let name: String
    public let description: String?
    public let version: String?
    public let avatarUrl: String?
}

public struct PluginCommandArg: Codable, Sendable, Hashable {
    public let name: String
    public let description: String?
    public let type: String
    public let required: Bool?
    public let sensitive: Bool?
}

public struct PluginCommand: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(pluginId).\(name)" }

    public let pluginId: String
    public let name: String
    public let description: String?
    public let args: [PluginCommandArg]?
}

/// `Record<pluginId, TCommandInfo[]>`.
public struct PluginCommandsMap: Codable, Sendable {
    public let entries: [String: [PluginCommand]]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entries = try container.decode([String: [PluginCommand]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }

    public init(entries: [String: [PluginCommand]] = [:]) {
        self.entries = entries
    }
}

public struct PluginCapability: Codable, Sendable, Hashable {
    public let type: String
    public let name: String
    public let description: String?
    public let configured: Bool
    public let requires: String?
    public let defaultAccess: PluginCapabilityAccess?
    public let mode: String?
    public let roleIds: [Int]?
}

public struct PluginCapabilityAccess: Codable, Sendable, Hashable {
    public let mode: String
    public let roleIds: [Int]
}

public struct PluginCapabilityAccessRule: Codable, Sendable, Hashable {
    public let pluginId: String
    public let type: String
    public let name: String
    public let roleIds: [Int]
}

public struct PluginSettingDefinition: Codable, Sendable {
    public let key: String
    public let name: String
    public let description: String?
    public let type: String
    public let defaultValue: JSONValue?
    public let options: [PluginSettingOption]?
}

public struct PluginSettingOption: Codable, Sendable {
    public let value: JSONValue?
    public let label: String
}

public struct PluginSettings: Codable, Sendable {
    public let definitions: [PluginSettingDefinition]
    public let values: [String: JSONValue]
    public let secretsSet: [String]?
}

public struct PluginLogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { hashValue }

    public let type: String
    public let timestamp: Int
    public let message: String
    public let pluginId: String
}

public struct PluginPushEvent: Codable, Sendable {
    public let pluginId: String
    public let data: JSONValue?
}

// MARK: - settings and server

public struct SharkordSettings: Codable, Sendable {
    public let name: String
    public let description: String?
    public let serverId: String
    public let storageUploadEnabled: Bool?
    public let directMessagesEnabled: Bool?
    public let storageQuota: Int?
    public let storageUploadMaxFileSize: Int?
    public let storageFileSharingInDirectMessages: Bool?
    public let storageMaxFilesPerMessage: Int?
    public let storageMaxAvatarSize: Int?
    public let storageMaxBannerSize: Int?
    public let storageSpaceQuotaByUser: Int?
    public let storageOverflowAction: String?
    public let enablePlugins: Bool?
    public let enableSearch: Bool?
    public let storageSignedUrlsEnabled: Bool?
    public let webRtcSimulcastEnabled: Bool?
    public let webRtcMaxBitrate: Int?
    public let showWelcomeDialog: Bool?
}

/// `others.getSettings`: the admin view, which carries the join password in the clear.
public struct SharkordAdminSettings: Codable, Sendable {
    public let name: String
    public let description: String?
    public let serverId: String
    public let password: String?
    public let onlyAskForPasswordOnFirstJoin: Bool?
    public let allowNewUsers: Bool?
    public let directMessagesEnabled: Bool?
    public let enablePlugins: Bool?
    public let enableSearch: Bool?
    public let showWelcomeDialog: Bool?
    public let webRtcSimulcastEnabled: Bool?
    public let logoId: Int?
    public let storageUploadEnabled: Bool?
    public let storageFileSharingInDirectMessages: Bool?
    public let storageQuota: Int?
    public let storageUploadMaxFileSize: Int?
    public let storageMaxAvatarSize: Int?
    public let storageMaxBannerSize: Int?
    public let storageMaxFilesPerMessage: Int?
    public let storageSpaceQuotaByUser: Int?
    public let storageOverflowAction: String?
    public let storageSignedUrlsEnabled: Bool?
    public let storageSignedUrlsTtlSeconds: Int?
    public let storageImageOptimizationEnabled: Bool?
    public let storageImageOptimizationQuality: Int?
}

public struct DiskMetrics: Codable, Sendable {
    public let totalSpace: Int
    public let usedSpace: Int
    public let freeSpace: Int
    public let sharkordUsedSpace: Int
}

public struct PluginStorageInfo: Codable, Sendable {
    public let pluginId: String
    public let fileCount: Int
    public let usedSpace: Int
    public let installed: Bool
}

/// The storage half of the server settings. `others.getStorageSettings` returns only these
/// fields, unlike `others.getSettings` which returns the whole record.
public struct StorageSettings: Codable, Sendable {
    public let storageUploadEnabled: Bool?
    public let storageFileSharingInDirectMessages: Bool?
    public let storageQuota: Int?
    public let storageUploadMaxFileSize: Int?
    public let storageMaxAvatarSize: Int?
    public let storageMaxBannerSize: Int?
    public let storageMaxFilesPerMessage: Int?
    public let storageSpaceQuotaByUser: Int?
    public let storageOverflowAction: String?
    public let storageSignedUrlsEnabled: Bool?
    public let storageSignedUrlsTtlSeconds: Int?
    public let storageImageOptimizationEnabled: Bool?
    public let storageImageOptimizationQuality: Int?
}

public struct StorageSettingsResult: Codable, Sendable {
    public let storageSettings: StorageSettings
    public let diskMetrics: DiskMetrics
    public let pluginStorage: [PluginStorageInfo]
}

public struct UpdateInfo: Codable, Sendable {
    public let canUpdate: Bool
    public let latestVersion: String
    public let hasUpdate: Bool
    public let currentVersion: String
}

public struct SharkordServerInfo: Codable, Sendable {
    public let serverId: String
    public let name: String
    public let description: String?
    public let logo: SharkordFile?
    public let allowNewUsers: Bool
    public let oidcEnabled: Bool?
    public let oidcDisableLocalLogin: Bool?
    public let version: String?
}

public struct SharkordLoginResult: Codable, Sendable {
    public let success: Bool?
    public let token: String
}

public struct SharkordHandshake: Codable, Sendable {
    public let handshakeHash: String
    public let hasPassword: Bool
}

// MARK: - join and events

/// The `others.joinServer` payload. Extra keys in the response are ignored by `Codable`.
public struct JoinResult: Codable, Sendable {
    public let categories: [SharkordCategory]
    public let channels: [SharkordChannel]
    public let users: [SharkordUser]
    public let serverId: String
    public let serverName: String
    public let ownUserId: Int
    public let ownUserPasswordSet: Bool?
    public let voiceMap: VoiceMap?
    public let roles: [SharkordRole]
    public let emojis: [SharkordEmoji]?
    public let publicSettings: SharkordSettings
    public let channelPermissions: ChannelPermissionsMap?
    public let readStates: [String: Int]?
    public let commands: PluginCommandsMap?
    public let pluginIdsWithComponents: [String]?
    public let pluginCapabilityAccess: [PluginCapabilityAccessRule]?
    public let pluginsMetadata: [PluginMetadata]?
    public let externalStreamsMap: ExternalStreamsMap?
    public let showWelcomeDialog: Bool?
}

public struct DirectMessageConversation: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { channelId }

    public let channelId: Int
    public let userId: Int
    public let unreadCount: Int
    public let lastMessageAt: Int
}

public struct ReadStateUpdate: Codable, Sendable {
    public let channelId: Int
    public let count: Int
}

public struct ReadStateDelta: Codable, Sendable {
    public let channelId: Int
    public let delta: Int
}

public struct TypingEvent: Codable, Sendable {
    public let channelId: Int
    public let userId: Int
    public let parentMessageId: Int?
}

public struct ReplyCountUpdate: Codable, Sendable {
    public let messageId: Int
    public let channelId: Int
    public let replyCount: Int
}

public struct MessageDeleteEvent: Codable, Sendable {
    public let messageId: Int
    public let channelId: Int
}

public struct UserDeleteEvent: Codable, Sendable {
    public let isWipe: Bool?
    public let userId: Int?
    public let deletedUserId: Int
}

public struct OpenDirectMessageResult: Codable, Sendable {
    public let channelId: Int
}

public struct ConversationOpenEvent: Codable, Sendable {
    public let channelId: Int
}

/// A reaction grouped for display: one chip per emoji with a count and whether the viewer
/// is among the reactors.
public struct ReactionGroup: Identifiable, Hashable {
    public var id: String { emoji }

    public let emoji: String
    public let count: Int
    public let mine: Bool
    public let file: SharkordFile?
}

public enum ProtocolDefaults {
    public static let messagesLimit = 100
    public static let messageMaxLength = 10_000
    public static let reactionEmojiMaxLength = 32
    public static let typingWindow: TimeInterval = 6
    public static let maxUserNameLength = 24
    public static let maxChannelNameLength = 27
    public static let maxCategoryNameLength = 32
    public static let maxFilesPerMessage = 20
    public static let ownerRoleId = 1
    public static let maxRoles = 100
}
