package com.timmysheep.cove.voice

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Build
import android.os.IBinder
import android.os.ResultReceiver
import androidx.core.content.IntentCompat
import com.timmysheep.cove.R

class VoiceCallService : Service() {
    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel(this)
    }

    @Suppress("InlinedApi")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultReceiver = intent?.let {
            IntentCompat.getParcelableExtra(it, EXTRA_FOREGROUND_RESULT_RECEIVER, ResultReceiver::class.java)
        }

        try {
            val snapshot = snapshotFrom(intent)
            when (intent?.action) {
                ACTION_START_CALL -> startForegroundFor(
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    snapshot
                )
                ACTION_START_MICROPHONE -> startForegroundFor(
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                    snapshot
                )
                ACTION_START_SCREEN -> {
                    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    if (intent.getBooleanExtra(EXTRA_INCLUDE_MICROPHONE, false)) {
                        types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    }
                    if (intent.getBooleanExtra(EXTRA_INCLUDE_CAMERA, false)) {
                        types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                    }
                    startForegroundFor(types, snapshot)
                }
                ACTION_START_CAMERA -> {
                    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    if (intent.getBooleanExtra(EXTRA_INCLUDE_MICROPHONE, false)) {
                        types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    }
                    if (intent.getBooleanExtra(EXTRA_INCLUDE_PROJECTION, false)) {
                        types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                    }
                    startForegroundFor(types, snapshot)
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

    private fun startForegroundFor(types: Int, snapshot: VoiceCallNotificationSnapshot?) {
        val notification = buildNotification(this, snapshot)
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
        const val ACTION_START_CAMERA = "com.timmysheep.cove.voice.START_CAMERA"
        const val EXTRA_INCLUDE_MICROPHONE = "includeMicrophone"
        const val EXTRA_INCLUDE_CAMERA = "includeCamera"
        const val EXTRA_INCLUDE_PROJECTION = "includeProjection"
        const val EXTRA_FOREGROUND_RESULT_RECEIVER = "foregroundResultReceiver"
        const val EXTRA_FOREGROUND_ERROR = "foregroundError"

        private const val CHANNEL_ID = "voice_call"
        private const val NOTIFICATION_ID = 20
        private const val EXTRA_CHANNEL_ID = "notificationChannelId"
        private const val EXTRA_CHANNEL_NAME = "notificationChannelName"
        private const val EXTRA_PARTICIPANT_COUNT = "notificationParticipantCount"
        private const val EXTRA_MICROPHONE_ENABLED = "notificationMicrophoneEnabled"
        private const val EXTRA_SPEAKER_ENABLED = "notificationSpeakerEnabled"

        internal fun createIntent(
            context: Context,
            action: String,
            snapshot: VoiceCallNotificationSnapshot
        ): Intent = Intent(context, VoiceCallService::class.java)
            .setAction(action)
            .putExtra(EXTRA_CHANNEL_ID, snapshot.channelId)
            .putExtra(EXTRA_CHANNEL_NAME, snapshot.channelName)
            .putExtra(EXTRA_PARTICIPANT_COUNT, snapshot.participantCount)
            .putExtra(EXTRA_MICROPHONE_ENABLED, snapshot.microphoneEnabled)
            .putExtra(EXTRA_SPEAKER_ENABLED, snapshot.speakerEnabled)

        internal fun updateNotification(context: Context, snapshot: VoiceCallNotificationSnapshot) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.activeNotifications.none { it.id == NOTIFICATION_ID }) return
            manager.notify(NOTIFICATION_ID, buildNotification(context, snapshot))
        }

        internal fun cancelNotification(context: Context) {
            context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        }

        private fun buildNotification(
            context: Context,
            snapshot: VoiceCallNotificationSnapshot?
        ): Notification {
            ensureNotificationChannel(context)
            val channelName = snapshot?.channelName?.takeIf(String::isNotBlank)
                ?: context.getString(R.string.voice_room)
            val participantCount = snapshot?.participantCount ?: 1
            val participantText = context.resources.getQuantityString(
                R.plurals.voice_call_participant_count,
                participantCount,
                participantCount
            )
            val microphoneEnabled = snapshot?.microphoneEnabled == true
            val speakerEnabled = snapshot?.speakerEnabled != false
            val speakerIcon = if (speakerEnabled) {
                android.R.drawable.ic_lock_silent_mode_off
            } else {
                android.R.drawable.ic_lock_silent_mode
            }
            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setContentTitle("$channelName · $participantText")
                .setContentText(
                    context.getString(
                        if (microphoneEnabled) R.string.voice_call_microphone_on
                        else R.string.voice_call_microphone_off
                    )
                )
                .setCategory(Notification.CATEGORY_CALL)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .addAction(
                    createAction(
                        context,
                        VoiceCallNotificationAction.TOGGLE_SPEAKER,
                        speakerIcon,
                        context.getString(
                            if (speakerEnabled) R.string.voice_control_disable_speaker
                            else R.string.voice_control_enable_speaker
                        )
                    )
                )
                .addAction(
                    createAction(
                        context,
                        VoiceCallNotificationAction.TOGGLE_MICROPHONE,
                        android.R.drawable.ic_btn_speak_now,
                        context.getString(
                            if (microphoneEnabled) R.string.voice_control_mute_microphone
                            else R.string.voice_control_unmute_microphone
                        )
                    )
                )
                .addAction(
                    createAction(
                        context,
                        VoiceCallNotificationAction.LEAVE_CALL,
                        android.R.drawable.ic_menu_close_clear_cancel,
                        context.getString(R.string.leave_voice)
                    )
                )

            return notification.build()
        }

        private fun createAction(
            context: Context,
            action: VoiceCallNotificationAction,
            iconResource: Int,
            title: CharSequence
        ): Notification.Action {
            val intent = Intent(context, VoiceCallNotificationActionReceiver::class.java)
                .setAction(action.intentAction)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                action.requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val icon = Icon.createWithResource(context, iconResource)
            return Notification.Action.Builder(icon, title, pendingIntent).build()
        }

        private fun ensureNotificationChannel(context: Context) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.voice_call_notification_channel),
                NotificationManager.IMPORTANCE_LOW
            )
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        private fun snapshotFrom(intent: Intent?): VoiceCallNotificationSnapshot? {
            if (intent?.hasExtra(EXTRA_CHANNEL_ID) != true) return null
            return VoiceCallNotificationSnapshot(
                channelId = intent.getIntExtra(EXTRA_CHANNEL_ID, 0),
                channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME).orEmpty(),
                participantCount = intent.getIntExtra(EXTRA_PARTICIPANT_COUNT, 1),
                microphoneEnabled = intent.getBooleanExtra(EXTRA_MICROPHONE_ENABLED, false),
                speakerEnabled = intent.getBooleanExtra(EXTRA_SPEAKER_ENABLED, true)
            )
        }
    }
}
