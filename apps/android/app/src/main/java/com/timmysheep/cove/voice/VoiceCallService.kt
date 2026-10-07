package com.timmysheep.cove.voice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
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
        when (intent?.action) {
            ACTION_START_MICROPHONE -> startForegroundFor(ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            ACTION_START_SCREEN -> {
                var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                if (intent.getBooleanExtra(EXTRA_INCLUDE_MICROPHONE, false)) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                startForegroundFor(types)
            }
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
        const val ACTION_START_MICROPHONE = "com.timmysheep.cove.voice.START_MICROPHONE"
        const val ACTION_START_SCREEN = "com.timmysheep.cove.voice.START_SCREEN"
        const val EXTRA_INCLUDE_MICROPHONE = "includeMicrophone"

        private const val CHANNEL_ID = "voice_call"
        private const val NOTIFICATION_ID = 20
    }
}
