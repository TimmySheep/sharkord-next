package com.timmysheep.cove

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.timmysheep.cove.data.AndroidCredentialStore
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

class CoveViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = CoveRepository()
    private val voiceEngine = CoveVoiceEngine(application, repository)
    private val credentialStore = AndroidCredentialStore(application)
    private val mutableHasSavedLogin = MutableStateFlow(false)
    private val mutableCredentialStorageFailed = MutableStateFlow(false)

    val state: StateFlow<SessionState> = repository.state
    val remoteVideoTracks: StateFlow<List<RemoteVideoTrack>> = voiceEngine.remoteVideoTracks
    val localCameraTrack = voiceEngine.localCameraTrack
    val hasSavedLogin: StateFlow<Boolean> = mutableHasSavedLogin.asStateFlow()
    val credentialStorageFailed: StateFlow<Boolean> = mutableCredentialStorageFailed.asStateFlow()

    init {
        val savedLogin = credentialStore.load()
        mutableHasSavedLogin.value = savedLogin != null
        savedLogin?.let { credentials ->
            viewModelScope.launch {
                repository.connect(
                    credentials.host,
                    credentials.identity,
                    credentials.password,
                    credentials.serverPassword
                )
            }
        }

        viewModelScope.launch {
            repository.state.collect { currentState ->
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
            }
            repository.connect(
                credentials.host,
                credentials.identity,
                credentials.password,
                credentials.serverPassword
            )
        }
    }

    fun forgetSavedLogin() {
        val cleared = credentialStore.clear()
        mutableHasSavedLogin.value = if (cleared) false else credentialStore.load() != null
        mutableCredentialStorageFailed.value = !cleared
    }

    fun disconnect() {
        viewModelScope.launch {
            try {
                voiceEngine.leave()
            } finally {
                repository.disconnect()
            }
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

    fun signalTyping(channelId: Int) = repository.signalTyping(channelId)

    fun openDirectMessage(userId: Int) {
        viewModelScope.launch { repository.openDirectMessage(userId) }
    }

    fun joinVoice(channelId: Int) {
        viewModelScope.launch { voiceEngine.join(channelId) }
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
}
