package com.timmysheep.cove.data

import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.json.jsonObject

class AttachmentPolicyTest {
    private fun state(settings: String = "{}", permitted: Boolean = true) = SessionState(
        ownUserId = 1,
        users = listOf(User(1, "self", roleIds = listOf(2))),
        roles = listOf(Role(2, "member", permissions = if (permitted) listOf("UPLOAD_FILES") else emptyList())),
        publicSettings = SharkordApi.protocolJson.parseToJsonElement(settings).jsonObject
    )
    private val channel = SharkordApi.protocolJson.parseToJsonElement("""{"id":1,"name":"test","type":"TEXT"}""").decode<Channel>()

    @Test
    fun uploadRequiresPermissionAndFeatureGates() {
        assertTrue(state().canUploadAttachments(channel))
        assertFalse(state(permitted = false).canUploadAttachments(channel))
        assertFalse(state("""{"storageUploadEnabled":false}""").canUploadAttachments(channel))
        assertFalse(state("""{"storageFileSharingInDirectMessages":false}""").canUploadAttachments(channel.copy(isDm = true)))
        assertTrue(state("""{"storageFileSharingInDirectMessages":false}""").canUploadAttachments(channel))
    }

    @Test
    fun slotsNeverGoNegative() {
        assertEquals(2, state("""{"storageMaxFilesPerMessage":3}""").attachmentSlots(1))
        assertEquals(0, state("""{"storageMaxFilesPerMessage":3}""").attachmentSlots(4))
        assertEquals(10, state().attachmentSlots(0))
    }

    @Test
    fun boundedReadAcceptsExactLimitAndRejectsOversize() {
        assertArrayEquals(byteArrayOf(1, 2), readAttachment(byteArrayOf(1, 2).inputStream(), 2, "too large"))
        try {
            readAttachment(byteArrayOf(1, 2, 3).inputStream(), 2, "too large")
            fail("must reject oversize data")
        } catch (error: IllegalArgumentException) {
            assertEquals("too large", error.message)
        }
    }
}
