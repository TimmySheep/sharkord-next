package com.timmysheep.cove.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.jsonObject

class ProtocolModelsTest {
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
