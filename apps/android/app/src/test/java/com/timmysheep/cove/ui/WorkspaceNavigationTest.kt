package com.timmysheep.cove.ui

import com.timmysheep.cove.data.VoiceConnectionStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkspaceNavigationTest {
    @Test
    fun doesNotReplaceAnExplicitChannelSelectionWithSavedState() {
        assertFalse(shouldRestoreSavedChannel(activeChannelId = null, requestedChannelId = 42))
    }

    @Test
    fun restoresSavedChannelOnlyWhenNoSelectionIsPending() {
        assertTrue(shouldRestoreSavedChannel(activeChannelId = null, requestedChannelId = null))
        assertFalse(shouldRestoreSavedChannel(activeChannelId = 42, requestedChannelId = null))
    }

    @Test
    fun returnsHomeWhenTheVoiceRoomDisconnects() {
        assertTrue(
            shouldReturnHomeAfterVoiceDisconnect(
                isVoiceRoom = true,
                voiceChannelId = null,
                voiceAttemptChannelId = null,
                status = VoiceConnectionStatus.DISCONNECTED
            )
        )
    }

    @Test
    fun keepsTheCurrentPageWhileVoiceIsConnectedOrConnecting() {
        assertFalse(
            shouldReturnHomeAfterVoiceDisconnect(
                isVoiceRoom = true,
                voiceChannelId = 42,
                voiceAttemptChannelId = 42,
                status = VoiceConnectionStatus.CONNECTED
            )
        )
        assertFalse(
            shouldReturnHomeAfterVoiceDisconnect(
                isVoiceRoom = true,
                voiceChannelId = null,
                voiceAttemptChannelId = 42,
                status = VoiceConnectionStatus.CONNECTING
            )
        )
    }

    @Test
    fun doesNotChangeAnotherPageWhenVoiceDisconnects() {
        assertFalse(
            shouldReturnHomeAfterVoiceDisconnect(
                isVoiceRoom = false,
                voiceChannelId = null,
                voiceAttemptChannelId = null,
                status = VoiceConnectionStatus.DISCONNECTED
            )
        )
    }
}
