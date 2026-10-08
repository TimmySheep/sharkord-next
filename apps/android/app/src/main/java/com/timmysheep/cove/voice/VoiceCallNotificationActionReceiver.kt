package com.timmysheep.cove.voice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow

internal enum class VoiceCallNotificationAction(val intentAction: String, val requestCode: Int) {
    TOGGLE_SPEAKER("com.timmysheep.cove.voice.TOGGLE_SPEAKER", 21),
    TOGGLE_MICROPHONE("com.timmysheep.cove.voice.TOGGLE_MICROPHONE", 22),
    LEAVE_CALL("com.timmysheep.cove.voice.LEAVE_CALL", 23);

    companion object {
        fun fromIntentAction(action: String?): VoiceCallNotificationAction? =
            entries.firstOrNull { it.intentAction == action }
    }
}

internal object VoiceCallNotificationActionBus {
    private val actionChannel = Channel<VoiceCallNotificationAction>(Channel.BUFFERED)

    val actions = actionChannel.receiveAsFlow()

    fun dispatch(action: String?) {
        VoiceCallNotificationAction.fromIntentAction(action)?.let(actionChannel::trySend)
    }
}

class VoiceCallNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        VoiceCallNotificationActionBus.dispatch(intent.action)
    }
}
