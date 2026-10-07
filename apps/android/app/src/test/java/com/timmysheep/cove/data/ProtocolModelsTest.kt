package com.timmysheep.cove.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

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
}
