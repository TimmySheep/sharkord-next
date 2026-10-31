package com.timmysheep.cove

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.timmysheep.cove.data.AndroidCredentialStore
import com.timmysheep.cove.data.AdminUser
import com.timmysheep.cove.data.CoveRepository
import com.timmysheep.cove.data.MessageFile
import com.timmysheep.cove.data.SavedLoginCredentials
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.hasServerPermission
import com.timmysheep.cove.voice.CoveVoiceEngine
import com.timmysheep.cove.voice.RemoteVideoTrack
import com.timmysheep.cove.voice.VoiceCallNotificationAction
import com.timmysheep.cove.voice.VoiceCallNotificationActionBus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import org.webrtc.EglBase

class CoveViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = CoveRepository()
    private val voiceEngine = CoveVoiceEngine(application, repository)
    private val credentialStore = AndroidCredentialStore(application)
    private val mutableHasSavedLogin = MutableStateFlow(false)
    private val mutableHasActiveSession = MutableStateFlow(false)
    private val mutableCredentialStorageFailed = MutableStateFlow(false)
    private val mutableStartupReady = MutableStateFlow(false)
    private val mutableUserRequestedDisconnect = MutableStateFlow(false)
    private val voicePreferences = application.getSharedPreferences("voice_preferences", Application.MODE_PRIVATE)
    private val mutableMicrophoneEnabledOnJoin = MutableStateFlow(
        voicePreferences.getBoolean(MICROPHONE_ENABLED_ON_JOIN_KEY, false)
    )

    val state: StateFlow<SessionState> = repository.state
    val remoteVideoTracks: StateFlow<List<RemoteVideoTrack>> = voiceEngine.remoteVideoTracks
    val localCameraTrack = voiceEngine.localCameraTrack
    val eglBaseContext: StateFlow<EglBase.Context?> = voiceEngine.eglBaseContext
    val activeSpeakerIds = voiceEngine.activeSpeakerIds
    val hasSavedLogin: StateFlow<Boolean> = mutableHasSavedLogin.asStateFlow()
    val hasActiveSession: StateFlow<Boolean> = mutableHasActiveSession.asStateFlow()
    val credentialStorageFailed: StateFlow<Boolean> = mutableCredentialStorageFailed.asStateFlow()
    val startupReady: StateFlow<Boolean> = mutableStartupReady.asStateFlow()
    val userRequestedDisconnect: StateFlow<Boolean> = mutableUserRequestedDisconnect.asStateFlow()
    val microphoneEnabledOnJoin: StateFlow<Boolean> = mutableMicrophoneEnabledOnJoin.asStateFlow()

    init {
        val savedLogin = credentialStore.load()
        val autoConnectEnabled = credentialStore.isAutoConnectEnabled()
        mutableHasSavedLogin.value = savedLogin != null
        mutableHasActiveSession.value = credentialStore.hasEstablishedSession()
        mutableUserRequestedDisconnect.value = savedLogin != null && !autoConnectEnabled
        if (savedLogin == null || !autoConnectEnabled) {
            mutableStartupReady.value = true
        } else {
            viewModelScope.launch {
                try {
                    repository.connect(
                        savedLogin.host,
                        savedLogin.identity,
                        savedLogin.password,
                        savedLogin.serverPassword
                    )
                } finally {
                    mutableStartupReady.value = true
                }
            }
        }

        viewModelScope.launch {
            repository.state.collect { currentState ->
                if (currentState.connected && !mutableUserRequestedDisconnect.value) markActiveSession()
                if (!currentState.connected && currentState.voiceChannelId != null) {
                    voiceEngine.leave()
                }
            }
        }

        viewModelScope.launch {
            VoiceCallNotificationActionBus.actions.collect { action ->
                when (action) {
                    VoiceCallNotificationAction.TOGGLE_SPEAKER -> {
                        voiceEngine.setSpeakerEnabled(!state.value.speakerEnabled)
                    }
                    VoiceCallNotificationAction.TOGGLE_MICROPHONE -> {
                        if (state.value.microphoneEnabled) {
                            voiceEngine.setMicrophoneEnabled(false)
                        } else {
                            if (!state.value.speakerEnabled) voiceEngine.setSpeakerEnabled(true)
                            if (state.value.speakerEnabled && !state.value.microphoneEnabled) {
                                voiceEngine.setMicrophoneEnabled(true)
                            }
                        }
                    }
                    VoiceCallNotificationAction.LEAVE_CALL -> voiceEngine.leave()
                }
            }
        }
    }

    fun connect(host: String, identity: String, password: String, serverPassword: String, rememberLogin: Boolean) {
        viewModelScope.launch {
            mutableCredentialStorageFailed.value = false
            if (!rememberLogin) {
                val cleared = credentialStore.clear()
                if (!cleared) {
                    mutableHasSavedLogin.value = credentialStore.load() != null
                    mutableCredentialStorageFailed.value = true
                    return@launch
                }
                mutableHasSavedLogin.value = false
            }

            repository.connect(host, identity, password, serverPassword)
            if (repository.state.value.connected) markActiveSession()

            if (rememberLogin && repository.state.value.connected) {
                val saved = credentialStore.save(
                    SavedLoginCredentials(host, identity, password, serverPassword)
                )
                mutableHasSavedLogin.value = saved
                mutableCredentialStorageFailed.value = !saved
                if (!saved) {
                    credentialStore.clear()
                    mutableHasSavedLogin.value = credentialStore.load() != null
                }
            }
        }
    }

    fun connectSavedLogin(rememberLogin: Boolean) {
        viewModelScope.launch {
            val credentials = credentialStore.load()
            if (credentials == null) {
                mutableHasSavedLogin.value = false
                mutableUserRequestedDisconnect.value = true
                return@launch
            }

            mutableCredentialStorageFailed.value = false
            if (!rememberLogin) {
                if (!credentialStore.clear()) {
                    mutableCredentialStorageFailed.value = true
                    return@launch
                }
                mutableHasSavedLogin.value = false
            } else {
                mutableHasSavedLogin.value = true
                if (!credentialStore.setAutoConnectEnabled(true)) {
                    mutableCredentialStorageFailed.value = true
                }
            }
            repository.connect(
                credentials.host,
                credentials.identity,
                credentials.password,
                credentials.serverPassword
            )
            if (repository.state.value.connected) markActiveSession()
        }
    }

    fun forgetSavedLogin() {
        val cleared = credentialStore.clear()
        mutableHasSavedLogin.value = if (cleared) false else credentialStore.load() != null
        if (cleared) mutableHasActiveSession.value = false
        mutableUserRequestedDisconnect.value = true
        mutableCredentialStorageFailed.value = !cleared
    }

    fun disconnect() {
        mutableUserRequestedDisconnect.value = true
        mutableHasActiveSession.value = false
        mutableCredentialStorageFailed.value = !credentialStore.markDisconnected()
        viewModelScope.launch {
            try {
                voiceEngine.leave()
            } finally {
                repository.disconnect()
            }
        }
    }

    private fun markActiveSession() {
        mutableUserRequestedDisconnect.value = false
        if (!mutableHasActiveSession.value) {
            mutableHasActiveSession.value = true
            credentialStore.setHasEstablishedSession(true)
        }
    }

    fun clearError() = repository.clearError()

    fun selectChannel(channelId: Int, targetMessageId: Int? = null) {
        viewModelScope.launch { repository.selectChannel(channelId, targetMessageId) }
    }

    fun closeChannel() = repository.closeChannel()

    fun loadOlder(channelId: Int) {
        viewModelScope.launch { repository.loadOlder(channelId) }
    }

    fun sendMessage(
        channelId: Int,
        text: String,
        replyToMessageId: Int?,
        fileIds: List<String> = emptyList(),
        parentMessageId: Int? = null,
        onComplete: (Boolean) -> Unit = {}
    ) {
        viewModelScope.launch {
            val sent = repository.sendMessage(channelId, text, replyToMessageId, fileIds, parentMessageId)
            onComplete(sent)
        }
    }

    suspend fun uploadAttachment(data: ByteArray, fileName: String, mimeType: String) =
        repository.uploadAttachment(data, fileName, mimeType)

    suspend fun updateOwnProfile(name: String, profileColor: String, bio: String) =
        repository.updateOwnProfile(name, profileColor, bio)

    suspend fun updateOwnPassword(currentPassword: String, newPassword: String, confirmNewPassword: String): Boolean {
        mutableCredentialStorageFailed.value = false
        val savedCredentials = credentialStore.load()
        val updated = repository.updateOwnPassword(currentPassword, newPassword, confirmNewPassword)
        if (!updated) return false

        if (savedCredentials != null) {
            val saved = credentialStore.save(savedCredentials.copy(password = newPassword))
            mutableHasSavedLogin.value = saved
            if (!saved) {
                credentialStore.setAutoConnectEnabled(false)
                credentialStore.clear()
                mutableHasSavedLogin.value = credentialStore.load() != null
                mutableCredentialStorageFailed.value = true
            }
        }
        return true
    }

    suspend fun changeOwnProfileImage(isAvatar: Boolean, fileId: String?) =
        repository.changeOwnProfileImage(isAvatar, fileId)

    suspend fun getAdminUsers(): List<AdminUser> = repository.getAdminUsers()

    suspend fun addUserRole(userId: Int, roleId: Int) = repository.addUserRole(userId, roleId)

    suspend fun removeUserRole(userId: Int, roleId: Int) = repository.removeUserRole(userId, roleId)

    suspend fun kickUser(userId: Int, reason: String) = repository.kickUser(userId, reason)

    suspend fun banUser(userId: Int, reason: String) = repository.banUser(userId, reason)

    suspend fun unbanUser(userId: Int) = repository.unbanUser(userId)

    suspend fun deleteUser(userId: Int, wipe: Boolean) = repository.deleteUser(userId, wipe)

    fun deleteTemporaryFile(fileId: String) {
        viewModelScope.launch { repository.deleteTemporaryFile(fileId) }
    }

    fun publicFileUrl(file: MessageFile): String? = repository.publicFileUrl(file)

    suspend fun downloadPublicFile(url: String): ByteArray = repository.downloadPublicFile(url)

    fun searchMessages(query: String) {
        viewModelScope.launch { repository.searchMessages(query) }
    }

    fun clearSearch() = repository.clearSearch()

    fun openThread(parentMessageId: Int, channelId: Int? = null) {
        viewModelScope.launch { repository.openThread(parentMessageId, channelId) }
    }

    fun openMessage(messageId: Int) {
        viewModelScope.launch { repository.openMessage(messageId) }
    }

    fun closeThread() = repository.closeThread()

    fun loadOlderThread(parentMessageId: Int) {
        viewModelScope.launch { repository.loadOlderThread(parentMessageId) }
    }

    fun editMessage(messageId: Int, text: String) {
        viewModelScope.launch { repository.editMessage(messageId, text) }
    }

    fun deleteMessage(messageId: Int) {
        viewModelScope.launch { repository.deleteMessage(messageId) }
    }

    fun togglePin(messageId: Int) {
        viewModelScope.launch { repository.togglePin(messageId) }
    }

    fun toggleReaction(messageId: Int, emoji: String) {
        viewModelScope.launch { repository.toggleReaction(messageId, emoji) }
    }

    fun signalTyping(channelId: Int, parentMessageId: Int? = null) = repository.signalTyping(channelId, parentMessageId)

    fun openDirectMessage(userId: Int, onComplete: (Boolean) -> Unit = {}) {
        viewModelScope.launch { onComplete(repository.openDirectMessage(userId)) }
    }

    fun joinVoice(channelId: Int) {
        viewModelScope.launch { voiceEngine.join(channelId, mutableMicrophoneEnabledOnJoin.value) }
    }

    fun setMicrophoneEnabledOnJoin(enabled: Boolean) {
        mutableMicrophoneEnabledOnJoin.value = enabled
        voicePreferences.edit().putBoolean(MICROPHONE_ENABLED_ON_JOIN_KEY, enabled).apply()
    }

    fun leaveVoice() {
        viewModelScope.launch { voiceEngine.leave() }
    }

    fun setMicrophoneEnabled(enabled: Boolean) {
        viewModelScope.launch { voiceEngine.setMicrophoneEnabled(enabled) }
    }

    fun setSpeakerEnabled(enabled: Boolean) {
        viewModelScope.launch { voiceEngine.setSpeakerEnabled(enabled) }
    }

    fun setCameraEnabled(enabled: Boolean) {
        viewModelScope.launch { voiceEngine.setCameraEnabled(enabled) }
    }

    fun switchCamera() = voiceEngine.switchCamera()

    fun setConsumerQuality(remoteId: Int, kind: String, spatialLayer: Int?) {
        viewModelScope.launch { repository.setConsumerQuality(remoteId, kind, spatialLayer) }
    }

    fun startScreenShare(resultCode: Int, data: Intent?) {
        viewModelScope.launch { voiceEngine.startScreenShare(resultCode, data) }
    }

    fun stopScreenShare() {
        viewModelScope.launch { voiceEngine.stopScreenShare() }
    }

    fun hasChannelPermission(channelId: Int, permission: String) =
        repository.canUseChannelPermission(channelId, permission)

    fun hasServerPermission(permission: String) = repository.canUseServerPermission(permission)

    fun refreshDirectMessages() {
        viewModelScope.launch { repository.refreshDirectMessages() }
    }

    override fun onCleared() {
        voiceEngine.release()
        repository.dispose()
        super.onCleared()
    }

    private companion object {
        const val MICROPHONE_ENABLED_ON_JOIN_KEY = "microphone_enabled_on_join"
    }
}
