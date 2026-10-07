package com.timmysheep.cove.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

@Serializable
enum class ChannelType {
    @SerialName("TEXT")
    TEXT,

    @SerialName("VOICE")
    VOICE
}

@Serializable
data class Category(
    val id: Int,
    val name: String,
    val position: Int = 0
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
    val mimeType: String = "application/octet-stream"
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
    val ownUserId: Int = 0,
    val categories: List<Category> = emptyList(),
    val channels: List<Channel> = emptyList(),
    val users: List<User> = emptyList(),
    val conversations: List<DirectMessageConversation> = emptyList(),
    val messagesByChannel: Map<Int, List<Message>> = emptyMap(),
    val messageCursors: Map<Int, MessagesCursor?> = emptyMap(),
    val voiceUsersByChannel: Map<Int, Map<Int, VoiceUserState>> = emptyMap(),
    val unreadByChannel: Map<Int, Int> = emptyMap(),
    val channelPermissions: JsonObject = JsonObject(emptyMap()),
    val publicSettings: JsonObject = JsonObject(emptyMap()),
    val activeChannelId: Int? = null,
    val voiceChannelId: Int? = null,
    val microphoneEnabled: Boolean = false,
    val speakerEnabled: Boolean = true,
    val sharingScreen: Boolean = false,
    val consumedRemoteStreams: Set<String> = emptySet()
)
