package com.timmysheep.cove.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonPrimitive
import com.timmysheep.cove.data.directMessagesEnabled

class ProtocolModelsTest {
    @Test
    fun decodesCustomEmojiJoinStateAndReactionImages() {
        val joined = SharkordApi.protocolJson.parseToJsonElement(
            """{"ownUserId":7,"serverName":"test","emojis":[{"id":3,"name":"wave","file":{"id":8,"name":"wave.png","mimeType":"image/png"}}]}"""
        ).decode<JoinResponse>()
        val reaction = SharkordApi.protocolJson.parseToJsonElement(
            """{"messageId":91,"userId":7,"emoji":"wave","fileId":8,"file":{"id":8,"name":"wave.png","mimeType":"image/png"}}"""
        ).decode<MessageReaction>()

        assertEquals("wave", joined.emojis.single().name)
        assertEquals("wave.png", reaction.file?.name)
        assertEquals(joined.emojis.single().file?.id, reaction.fileId)
    }

    @Test
    fun acceptsAbsentCustomEmojiCollectionsAndUnicodeReactionFiles() {
        val joined = SharkordApi.protocolJson.parseToJsonElement(
            """{"ownUserId":7,"serverName":"test"}"""
        ).decode<JoinResponse>()
        val reaction = SharkordApi.protocolJson.parseToJsonElement(
            """{"messageId":91,"emoji":"👍"}"""
        ).decode<MessageReaction>()

        assertTrue(joined.emojis.isEmpty())
        assertEquals(null, reaction.file)
    }

    @Test
    fun readsDirectMessageAvailabilityFromServerSettings() {
        val enabledSettings = SharkordApi.protocolJson.parseToJsonElement("""{"directMessagesEnabled":true}""").jsonObject
        val disabledSettings = SharkordApi.protocolJson.parseToJsonElement("""{"directMessagesEnabled":false}""").jsonObject

        assertTrue(SessionState(publicSettings = enabledSettings).directMessagesEnabled)
        assertFalse(SessionState(publicSettings = disabledSettings).directMessagesEnabled)
        assertFalse(SessionState().directMessagesEnabled)
    }

    @Test
    fun decodesOwnProfileFieldsAndImageFiles() {
        val user = SharkordApi.protocolJson.parseToJsonElement(
            """{"id":7,"name":"viewer","profileColor":"#123456","bio":"Hello","avatar":{"id":8,"name":"avatar.png","mimeType":"image/png"},"banner":{"id":9,"name":"banner.jpg","mimeType":"image/jpeg"}}"""
        ).decode<User>()

        assertEquals("Hello", user.bio)
        assertEquals("avatar.png", user.avatar?.name)
        assertEquals("banner.jpg", user.banner?.name)
    }

    @Test
    fun decodesWhetherTheOwnAccountCanChangeItsPassword() {
        val response = SharkordApi.protocolJson.parseToJsonElement(
            """{"ownUserId":7,"serverName":"test","ownUserPasswordSet":false}"""
        ).decode<JoinResponse>()

        assertFalse(response.ownUserPasswordSet)
    }

    @Test
    fun decodesAdminUserManagementFields() {
        val user = SharkordApi.protocolJson.parseToJsonElement(
            """{"id":9,"name":"member","createdAt":100,"lastLoginAt":200,"banned":true,"banReason":"spam","bannedAt":150,"roleIds":[2],"avatar":{"id":8,"name":"avatar.png"},"identity":"private","password":"ignored"}"""
        ).decode<AdminUser>()

        assertEquals(9, user.id)
        assertEquals(100L, user.createdAt)
        assertEquals(200L, user.lastLoginAt)
        assertEquals("spam", user.banReason)
        assertEquals(listOf(2), user.roleIds)
        assertEquals("avatar.png", user.avatar?.name)
    }

    @Test
    fun onlyOtherRealUsersCanBeBannedOrDeleted() {
        val target = AdminUser(id = 9, name = "member")
        val deletedPlaceholder = AdminUser(id = 10, name = DELETED_USER_PLACEHOLDER)

        assertTrue(canBanOrDeleteUser(target, ownUserId = 7))
        assertFalse(canBanOrDeleteUser(target, ownUserId = 9))
        assertFalse(canBanOrDeleteUser(deletedPlaceholder, ownUserId = 7))
    }

    @Test
    fun decodesChannelWireFieldsAndDefaults() {
        val channel = SharkordApi.protocolJson.parseToJsonElement(
            """{"id":17,"type":"VOICE","name":"studio","private":true,"isDm":false,"position":3,"categoryId":2,"createdAt":1720000000000}"""
        ).decode<Channel>()

        assertEquals(17, channel.id)
        assertEquals(ChannelType.VOICE, channel.type)
        assertTrue(channel.isPrivate)
        assertEquals(null, channel.topic)
    }

    @Test
    fun decodesJoinedMessagesAndIgnoresServerOnlyFields() {
        val message = SharkordApi.protocolJson.parseToJsonElement(
            """{"id":91,"content":"<p>hello</p>","userId":4,"channelId":17,"parentMessageId":null,"replyToMessageId":90,"editable":true,"createdAt":1720000000000,"editedAt":null,"pinned":true,"files":[{"id":8,"name":"image.png","originalName":"image.png","size":128,"mimeType":"image/png","path":"/uploads/image.png"}],"reactions":[{"messageId":91,"userId":4,"emoji":"👍","pluginId":null,"createdAt":1720000000001}],"replyCount":2,"replyTo":{"id":90,"content":"<p>question</p>","userId":3,"pluginId":null},"pluginId":null}"""
        ).decode<Message>()

        assertEquals(91, message.id)
        assertEquals("image.png", message.files.single().originalName)
        assertEquals("👍", message.reactions.single().emoji)
        assertEquals(90, message.replyTo?.id)
        assertEquals(2, message.replyCount)
        assertTrue(message.pinned)
    }

    @Test
    fun decodesVoiceProducerListsWithOptionalDefaults() {
        val producers = SharkordApi.protocolJson.parseToJsonElement(
            """{"remoteAudioIds":[4],"remoteScreenIds":[8]}"""
        ).decode<RemoteProducerIds>()

        assertEquals(listOf(4), producers.remoteAudioIds)
        assertEquals(listOf(8), producers.remoteScreenIds)
        assertTrue(producers.remoteVideoIds.isEmpty())
        assertFalse(producers.remoteAudioIds.contains(8))
    }

    @Test
    fun decodesProducerIdsFromBareAndWrappedRpcResults() {
        assertEquals("producer-id", JsonPrimitive("producer-id").decodeProducerId())
        assertEquals(
            "producer-id",
            SharkordApi.protocolJson.parseToJsonElement("""{"value":"producer-id"}""").decodeProducerId()
        )
    }

    @Test(expected = RpcException::class)
    fun rejectsNullProducerIds() {
        SharkordApi.protocolJson.parseToJsonElement("null").decodeProducerId()
    }

    @Test
    fun decodesVoiceQualityLayersAndPermissionState() {
        val result = SharkordApi.protocolJson.parseToJsonElement(
            """{"producerId":"producer","consumerId":"consumer","consumerKind":"video","consumerRtpParameters":{},"consumerType":"simulcast","qualityLayers":[{"spatialLayer":0,"label":"Low"},{"spatialLayer":2,"label":"High"}]}"""
        ).decode<ConsumeResult>()

        assertEquals(listOf(0, 2), result.qualityLayers.map(VoiceQualityLayer::spatialLayer))
        assertEquals(listOf("Low", "High"), result.qualityLayers.map(VoiceQualityLayer::label))

        val state = SessionState(
            ownUserId = 7,
            users = listOf(User(id = 7, name = "viewer", roleIds = listOf(3))),
            roles = listOf(Role(id = 3, name = "moderator", permissions = listOf("ENABLE_WEBCAM"))),
            channels = listOf(
                SharkordApi.protocolJson.parseToJsonElement(
                    """{"id":42,"type":"VOICE","name":"room"}"""
                ).decode<Channel>()
            ),
            channelPermissions = SharkordApi.protocolJson.parseToJsonElement(
                """{"42":{"permissions":{"WEBCAM":true,"SHARE_SCREEN":false}}}"""
            ).jsonObject
        )

        assertTrue(state.hasServerPermission("ENABLE_WEBCAM"))
        assertFalse(state.hasServerPermission("SHARE_SCREEN"))
        assertTrue(state.hasChannelPermission(42, "WEBCAM"))
        assertFalse(state.hasChannelPermission(42, "SHARE_SCREEN"))
    }
}
