package com.timmysheep.cove.ui

import com.timmysheep.cove.data.VoiceConnectionStatus

internal fun shouldRestoreSavedChannel(activeChannelId: Int?, requestedChannelId: Int?): Boolean =
    activeChannelId == null && requestedChannelId == null

internal fun shouldReturnHomeAfterVoiceDisconnect(
    isVoiceRoom: Boolean,
    voiceChannelId: Int?,
    voiceAttemptChannelId: Int?,
    status: VoiceConnectionStatus
): Boolean = isVoiceRoom &&
    voiceChannelId == null &&
    voiceAttemptChannelId == null &&
    status == VoiceConnectionStatus.DISCONNECTED
