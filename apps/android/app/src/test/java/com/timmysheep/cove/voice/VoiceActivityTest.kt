package com.timmysheep.cove.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceActivityTest {
    @Test
    fun readsProducerAudioLevelStats() {
        assertEquals(
            0.12f,
            requireNotNull(producerAudioLevel("""[{"type":"media-source","audioLevel":0.12}]""")),
            0.0001f
        )
    }

    @Test
    fun readsConsumerAudioLevelStats() {
        assertEquals(
            0.08f,
            requireNotNull(consumerAudioLevel("""[{"type":"inbound-rtp","audioLevel":0.08}]""")),
            0.0001f
        )
    }

    @Test
    fun ignoresUnrelatedAndMalformedStats() {
        assertNull(consumerAudioLevel("""[{"type":"outbound-rtp","audioLevel":0.8}]"""))
        assertNull(producerAudioLevel("not json"))
    }

    @Test
    fun detectsSpeakingAcrossNormalizedAndPercentAudioLevels() {
        assertTrue(isVoiceSpeaking(0.03f))
        assertFalse(isVoiceSpeaking(0.02f))
        assertTrue(isVoiceSpeaking(6f))
        assertFalse(isVoiceSpeaking(5f))
        assertFalse(isVoiceSpeaking(Float.NaN))
        assertFalse(isVoiceSpeaking(null))
    }
}
