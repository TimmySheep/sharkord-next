package com.timmysheep.cove.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ChannelDestinationTest {
    @Test
    fun countsVoiceParticipantsWithoutExposingTheirNames() {
        assertEquals(1, voiceParticipantCount(setOf(7)))
    }

    @Test
    fun countsMultipleVoiceParticipants() {
        assertEquals(3, voiceParticipantCount(setOf(9, 7, 8)))
    }

    @Test
    fun emptyVoiceChannelHasZeroParticipants() {
        assertEquals(0, voiceParticipantCount(emptySet()))
    }
}
