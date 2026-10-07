package com.timmysheep.cove.voice

import com.timmysheep.cove.data.SessionState

internal data class VoiceCallNotificationSnapshot(
    val channelId: Int,
    val channelName: String,
    val participantCount: Int,
    val microphoneEnabled: Boolean,
    val speakerEnabled: Boolean
) {
    companion object {
        fun from(state: SessionState): VoiceCallNotificationSnapshot? {
            val channelId = state.voiceChannelId ?: return null
            val participants = state.voiceUsersByChannel[channelId].orEmpty()
            val ownUserIsListed = state.ownUserId in participants

            return VoiceCallNotificationSnapshot(
                channelId = channelId,
                channelName = state.channels.firstOrNull { it.id == channelId }?.name.orEmpty(),
                participantCount = participants.size + if (ownUserIsListed) 0 else 1,
                microphoneEnabled = state.microphoneEnabled,
                speakerEnabled = state.speakerEnabled
            )
        }
    }
}
