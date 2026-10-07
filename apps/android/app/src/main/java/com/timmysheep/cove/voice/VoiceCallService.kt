package com.timmysheep.cove.voice

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Bundle
import android.os.Build
import android.os.IBinder
import android.os.ResultReceiver
import androidx.core.content.IntentCompat
import com.timmysheep.cove.R

class VoiceCallService : Service() {
    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.voice_call_notification_channel),
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    @Suppress("InlinedApi")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultReceiver = intent?.let {
            IntentCompat.getParcelableExtra(it, EXTRA_FOREGROUND_RESULT_RECEIVER, ResultReceiver::class.java)
        }

        try {
            when (intent?.action) {
                ACTION_START_CALL -> startForegroundFor(ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                ACTION_START_MICROPHONE -> startForegroundFor(
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
                ACTION_START_SCREEN -> {
                    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    if (intent.getBooleanExtra(EXTRA_INCLUDE_MICROPHONE, false)) {
                        types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    }
                    startForegroundFor(types)
                }
            }
            resultReceiver?.send(Activity.RESULT_OK, Bundle.EMPTY)
        } catch (error: RuntimeException) {
            resultReceiver?.send(
                Activity.RESULT_CANCELED,
                Bundle().apply { putString(EXTRA_FOREGROUND_ERROR, error.message) }
            )
            if (resultReceiver == null) throw error
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundFor(types: Int) {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle(getString(R.string.voice_call_notification_title))
            .setContentText(getString(R.string.voice_call_notification_body))
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, types)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_START_CALL = "com.timmysheep.cove.voice.START_CALL"
        const val ACTION_START_MICROPHONE = "com.timmysheep.cove.voice.START_MICROPHONE"
        const val ACTION_START_SCREEN = "com.timmysheep.cove.voice.START_SCREEN"
        const val EXTRA_INCLUDE_MICROPHONE = "includeMicrophone"
        const val EXTRA_FOREGROUND_RESULT_RECEIVER = "foregroundResultReceiver"
        const val EXTRA_FOREGROUND_ERROR = "foregroundError"

        private const val CHANNEL_ID = "voice_call"
        private const val NOTIFICATION_ID = 20
    }
}
