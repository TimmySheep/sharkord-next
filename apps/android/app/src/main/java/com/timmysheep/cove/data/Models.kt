package com.timmysheep.cove.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

@Serializable
enum class ChannelType {
    @SerialName("TEXT")
    TEXT,

    @SerialName("VOICE")
    VOICE
}

enum class VoiceConnectionStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED
}

@Serializable
data class Category(
    val id: Int,
    val name: String,
    val position: Int = 0
)

@Serializable
data class Role(
    val id: Int,
    val name: String,
    val color: String = "",
    val isPersistent: Boolean = false,
    val isDefault: Boolean = false,
    val permissions: List<String> = emptyList()
)

@Serializable
data class Channel(
    val id: Int,
    val type: ChannelType,
    val name: String,
    val topic: String? = null,
    @SerialName("private") val isPrivate: Boolean = false,
    val isDm: Boolean = false,
    val position: Int = 0,
    val categoryId: Int? = null,
    val createdAt: Long = 0
)

@Serializable
data class User(
    val id: Int,
    val name: String,
    val profileColor: String = "",
    val bio: String = "",
    val avatar: MessageFile? = null,
    val banner: MessageFile? = null,
    val banned: Boolean = false,
    val status: String? = null,
    val roleIds: List<Int> = emptyList()
)

@Serializable
data class VoiceUserState(
    val micMuted: Boolean = true,
    val soundMuted: Boolean = false,
    val webcamEnabled: Boolean = false,
    val sharingScreen: Boolean = false
)

@Serializable
data class MessageReaction(
    val messageId: Int,
    val userId: Int? = null,
    val emoji: String,
    val fileId: Int? = null
)

@Serializable
data class MessageFile(
    val id: Int,
    val name: String,
    val originalName: String = name,
    val size: Long = 0,
    val mimeType: String = "application/octet-stream",
    val _accessToken: String? = null,
    val _accessTokenExpiresAt: Long? = null
)

@Serializable
data class TemporaryFile(
    val id: String,
    val originalName: String,
    val size: Long = 0,
    val md5: String = "",
    val path: String = "",
    val extension: String = "",
    val userId: Int? = null
)

@Serializable
data class ServerInfo(
    val name: String,
    val logo: MessageFile? = null
)

@Serializable
data class ReplyPreview(
    val id: Int,
    val content: String? = null,
    val userId: Int? = null
)

@Serializable
data class Message(
    val id: Int,
    val content: String? = null,
    val userId: Int? = null,
    val channelId: Int,
    val parentMessageId: Int? = null,
    val replyToMessageId: Int? = null,
    val editable: Boolean? = null,
    val createdAt: Long = 0,
    val editedAt: Long? = null,
    val pinned: Boolean = false,
    val files: List<MessageFile> = emptyList(),
    val reactions: List<MessageReaction> = emptyList(),
    val replyCount: Int = 0,
    val replyTo: ReplyPreview? = null
)

@Serializable
data class MessagesCursor(
    val createdAt: Long,
    val id: Int
)

@Serializable
data class MessagesPage(
    val messages: List<Message> = emptyList(),
    val nextCursor: MessagesCursor? = null,
    val hasNewer: Boolean = false
)

@Serializable
data class ThreadMessagesPage(
    val messages: List<Message> = emptyList(),
    val nextCursor: MessagesCursor? = null
)

@Serializable
data class SearchMessage(
    val id: Int,
    val channelId: Int,
    val channelName: String,
    val plainContent: String = "",
    val userId: Int? = null,
    val parentMessageId: Int? = null,
    val files: List<MessageFile> = emptyList(),
    val createdAt: Long = 0
)

@Serializable
data class SearchFile(
    val file: MessageFile,
    val messageId: Int,
    val channelId: Int,
    val messageContent: String? = null,
    val messageCreatedAt: Long = 0,
    val channelName: String,
    val channelIsDm: Boolean = false
)

@Serializable
data class MessageSearchResult(
    val messages: List<SearchMessage> = emptyList(),
    val files: List<SearchFile> = emptyList(),
    val truncated: Boolean = false
)

@Serializable
data class ThreadReplyCountEvent(
    val messageId: Int,
    val channelId: Int,
    val replyCount: Int
)

@Serializable
data class DirectMessageConversation(
    val channelId: Int,
    val userId: Int,
    val unreadCount: Int = 0,
    val lastMessageAt: Long = 0
)

@Serializable
data class LoginResponse(
    val success: Boolean? = null,
    val token: String
)

@Serializable
data class Handshake(
    val handshakeHash: String,
    val hasPassword: Boolean = false
)

@Serializable
data class JoinResponse(
    val categories: List<Category> = emptyList(),
    val channels: List<Channel> = emptyList(),
    val users: List<User> = emptyList(),
    val roles: List<Role> = emptyList(),
    val ownUserId: Int,
    val serverName: String,
    val voiceMap: JsonObject = JsonObject(emptyMap()),
    val channelPermissions: JsonObject = JsonObject(emptyMap()),
    val readStates: JsonObject = JsonObject(emptyMap()),
    val publicSettings: JsonObject = JsonObject(emptyMap())
)

@Serializable
data class VoiceJoinEvent(
    val channelId: Int,
    val userId: Int,
    val state: VoiceUserState? = null
)

@Serializable
data class VoiceLeaveEvent(
    val channelId: Int,
    val userId: Int
)

@Serializable
data class VoiceProducerEvent(
    val channelId: Int,
    val remoteId: Int,
    val kind: String
)

@Serializable
data class RemoteProducerIds(
    val remoteVideoIds: List<Int> = emptyList(),
    val remoteAudioIds: List<Int> = emptyList(),
    val remoteScreenIds: List<Int> = emptyList(),
    val remoteScreenAudioIds: List<Int> = emptyList(),
    val remoteExternalStreamIds: List<Int> = emptyList()
)

@Serializable
data class VoiceTransportParams(
    val id: String,
    val iceParameters: JsonObject,
    val iceCandidates: JsonArray,
    val dtlsParameters: JsonObject
)

@Serializable
data class ConsumeResult(
    val producerId: String,
    val consumerId: String,
    val consumerKind: String,
    val consumerRtpParameters: JsonObject,
    val consumerType: String,
    val qualityLayers: List<VoiceQualityLayer> = emptyList()
)

@Serializable
data class VoiceQualityLayer(
    val spatialLayer: Int,
    val label: String
)

@Serializable
data class MessageDeleteEvent(
    val messageId: Int,
    val channelId: Int
)

@Serializable
data class OpenDirectMessageResponse(
    val channelId: Int
)

data class VoiceParticipant(
    val user: User,
    val state: VoiceUserState
)

data class SessionState(
    val connected: Boolean = false,
    val connecting: Boolean = false,
    val error: String? = null,
    val serverAddress: String = "",
    val serverName: String = "",
    val serverLogo: MessageFile? = null,
    val ownUserId: Int = 0,
    val categories: List<Category> = emptyList(),
    val channels: List<Channel> = emptyList(),
    val users: List<User> = emptyList(),
    val roles: List<Role> = emptyList(),
    val conversations: List<DirectMessageConversation> = emptyList(),
    val directMessagesLoaded: Boolean = false,
    val messagesByChannel: Map<Int, List<Message>> = emptyMap(),
    val messageCursors: Map<Int, MessagesCursor?> = emptyMap(),
    val threadMessagesByParent: Map<Int, List<Message>> = emptyMap(),
    val threadCursors: Map<Int, MessagesCursor?> = emptyMap(),
    val activeThreadParentId: Int? = null,
    val highlightedMessageId: Int? = null,
    val searchResult: MessageSearchResult? = null,
    val isSearching: Boolean = false,
    val searchError: String? = null,
    val voiceUsersByChannel: Map<Int, Map<Int, VoiceUserState>> = emptyMap(),
    val unreadByChannel: Map<Int, Int> = emptyMap(),
    val channelPermissions: JsonObject = JsonObject(emptyMap()),
    val publicSettings: JsonObject = JsonObject(emptyMap()),
    val activeChannelId: Int? = null,
    val voiceChannelId: Int? = null,
    val voiceAttemptChannelId: Int? = null,
    val voiceConnectionStatus: VoiceConnectionStatus = VoiceConnectionStatus.DISCONNECTED,
    val microphoneEnabled: Boolean = false,
    val speakerEnabled: Boolean = true,
    val sharingScreen: Boolean = false,
    val cameraEnabled: Boolean = false,
    val consumedRemoteStreams: Set<String> = emptySet()
)

val SessionState.directMessagesEnabled: Boolean
    get() = publicSettings["directMessagesEnabled"]?.jsonPrimitive?.booleanOrNull == true

private const val OWNER_ROLE_ID = 1

fun SessionState.hasServerPermission(permission: String): Boolean {
    val roleIds = users.firstOrNull { it.id == ownUserId }?.roleIds.orEmpty()
    return roleIds.any { roleId ->
        roleId == OWNER_ROLE_ID || roles.any { role ->
            role.id == roleId && permission in role.permissions
        }
    }
}

fun SessionState.hasChannelPermission(channelId: Int, permission: String): Boolean {
    if (channels.firstOrNull { it.id == channelId }?.isDm == true) return true
    return channelPermissions[channelId.toString()]
        ?.jsonObject?.get("permissions")?.jsonObject
        ?.get(permission)?.jsonPrimitive?.booleanOrNull == true
}
