package com.timmysheep.cove.voice

import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.VoiceUserState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceCallNotificationSnapshotTest {
    @Test
    fun includesChannelNameMediaStateAndOwnUserInParticipantCount() {
        val snapshot = VoiceCallNotificationSnapshot.from(
            SessionState(
                ownUserId = 1,
                channels = listOf(Channel(id = 10, type = ChannelType.VOICE, name = "Lounge")),
                voiceChannelId = 10,
                microphoneEnabled = true,
                speakerEnabled = false,
                voiceUsersByChannel = mapOf(
                    10 to mapOf(2 to VoiceUserState(), 3 to VoiceUserState())
                )
            )
        )

        assertEquals("Lounge", snapshot?.channelName)
        assertEquals(3, snapshot?.participantCount)
        assertTrue(snapshot?.microphoneEnabled == true)
        assertFalse(snapshot?.speakerEnabled == true)
    }

    @Test
    fun doesNotCountOwnUserTwice() {
        val snapshot = VoiceCallNotificationSnapshot.from(
            SessionState(
                ownUserId = 1,
                voiceChannelId = 10,
                voiceUsersByChannel = mapOf(
                    10 to mapOf(1 to VoiceUserState(), 2 to VoiceUserState())
                )
            )
        )

        assertEquals(2, snapshot?.participantCount)
    }

    @Test
    fun hasNoSnapshotWhenNotInVoice() {
        assertNull(VoiceCallNotificationSnapshot.from(SessionState()))
    }

    @Test
    fun mapsOnlyKnownNotificationActions() {
        assertEquals(
            VoiceCallNotificationAction.TOGGLE_SPEAKER,
            VoiceCallNotificationAction.fromIntentAction("com.timmysheep.cove.voice.TOGGLE_SPEAKER")
        )
        assertEquals(
            VoiceCallNotificationAction.TOGGLE_MICROPHONE,
            VoiceCallNotificationAction.fromIntentAction("com.timmysheep.cove.voice.TOGGLE_MICROPHONE")
        )
        assertEquals(
            VoiceCallNotificationAction.LEAVE_CALL,
            VoiceCallNotificationAction.fromIntentAction("com.timmysheep.cove.voice.LEAVE_CALL")
        )
        assertNull(VoiceCallNotificationAction.fromIntentAction("unrecognized"))
    }
}
