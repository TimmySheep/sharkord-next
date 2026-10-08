package com.timmysheep.cove.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.IOException

class SavedLoginCodecTest {
    @Test
    fun encodesAndDecodesAllLoginFields() {
        val credentials = SavedLoginCredentials(
            host = "https://例子.test/path?x=a|b",
            identity = "名字@example.test",
            password = "p|ass\nword",
            serverPassword = "🔒"
        )

        assertEquals(credentials, SavedLoginCodec.decode(SavedLoginCodec.encode(credentials)))
    }

    @Test
    fun rejectsPayloadWithTrailingData() {
        val payload = SavedLoginCodec.encode(SavedLoginCredentials("host", "user", "pass", "")) + byteArrayOf(1)

        assertThrows(IOException::class.java) { SavedLoginCodec.decode(payload) }
    }
}
