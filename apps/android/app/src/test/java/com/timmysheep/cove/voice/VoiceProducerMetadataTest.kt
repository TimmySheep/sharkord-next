package com.timmysheep.cove.voice

import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceProducerMetadataTest {
    @Test
    fun readsScreenKindFromProducerAppData() {
        assertEquals("screen", producerKindFromAppData("video", """{"kind":"screen"}"""))
    }

    @Test
    fun fallsBackToWebRtcKindWhenAppDataIsMissingOrInvalid() {
        assertEquals("video", producerKindFromAppData("video", "null"))
        assertEquals("audio", producerKindFromAppData("audio", "not-json"))
    }
}
