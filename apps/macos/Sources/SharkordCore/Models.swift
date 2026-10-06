import Foundation

/// Decodable models for the subset of the protocol the client renders. Field names match
/// the server's camelCase JSON. Everything optional except the fields the UI cannot do
/// without, so a server that grows a field does not break decoding.
public enum ChannelType: String, Codable, Sendable {
    case text = "TEXT"
    case voice = "VOICE"
}

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

public enum UserStatus: String, Codable, Sendable {
    case online
    case idle
    case offline
}

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
    public let roleIds: [Int]?
    public let _identity: String?

    func withStatus(_ status: UserStatus?) -> SharkordUser {
        var copy = self
        copy.status = status

        return copy
    }
}

public struct SharkordRole: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let color: String
    public let isPersistent: Bool
    public let isDefault: Bool
    public let permissions: [String]?
    public let createdAt: Int
    public let updatedAt: Int?
}

public struct SharkordMessageReaction: Codable, Sendable, Hashable {
    public let messageId: Int
    public let userId: Int
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

public struct SharkordMessage: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let content: String?
    public let userId: Int?
    public let pluginId: String?
    public let channelId: Int
    public let parentMessageId: Int?
    public let replyToMessageId: Int?
    public let editable: Bool?
    public let createdAt: Int
    public let updatedAt: Int?
    public let pinned: Bool?
    public let editedAt: Int?
    public let files: [SharkordFile]?
    public let reactions: [SharkordMessageReaction]?
    public let replyCount: Int?
    public let replyTo: SharkordReplyPreview?
}

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
    public let enablePlugins: Bool?
    public let enableSearch: Bool?
    public let storageSignedUrlsEnabled: Bool?
    public let webRtcMaxBitrate: Int?
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

public struct MessagesCursor: Codable, Sendable, Hashable {
    public let createdAt: Int
    public let id: Int
}

public struct MessagesPage: Codable, Sendable {
    public let messages: [SharkordMessage]
    public let nextCursor: MessagesCursor?
    public let hasNewer: Bool?
}

/// The `others.joinServer` payload. Only the fields the client uses are declared; extra
/// keys in the response are ignored by `Codable`.
public struct JoinResult: Codable, Sendable {
    public let categories: [SharkordCategory]
    public let channels: [SharkordChannel]
    public let users: [SharkordUser]
    public let roles: [SharkordRole]
    public let emojis: [SharkordEmoji]?
    public let serverId: String
    public let serverName: String
    public let ownUserId: Int
    public let ownUserPasswordSet: Bool?
    public let publicSettings: SharkordSettings
    public let readStates: [String: Int]?
    public let showWelcomeDialog: Bool?
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

public struct SharkordEmoji: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let fileId: Int
    public let userId: Int?
    public let createdAt: Int
    public let file: SharkordFile?
    public let user: SharkordPublicUser?
}

/// The sender fields the server trims for a public user (`TJoinedPublicUser` without identity).
public struct SharkordPublicUser: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let profileColor: String?
    public let avatar: SharkordFile?
    public let banner: SharkordFile?
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

public struct OpenDirectMessageResult: Codable, Sendable {
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
    public static let typingWindow: TimeInterval = 6
}
