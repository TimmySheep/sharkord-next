package com.timmysheep.cove

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.timmysheep.cove.data.CoveRepository
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.voice.CoveVoiceEngine
import com.timmysheep.cove.voice.RemoteVideoTrack
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class CoveViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = CoveRepository()
    private val voiceEngine = CoveVoiceEngine(application, repository)

    val state: StateFlow<SessionState> = repository.state
    val remoteVideoTracks: StateFlow<List<RemoteVideoTrack>> = voiceEngine.remoteVideoTracks

    init {
        viewModelScope.launch {
            repository.state.collect { currentState ->
                if (!currentState.connected && currentState.voiceChannelId != null) {
                    voiceEngine.leave()
                }
            }
        }
    }

    fun connect(host: String, identity: String, password: String, serverPassword: String) {
        viewModelScope.launch { repository.connect(host, identity, password, serverPassword) }
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

    fun selectChannel(channelId: Int) {
        viewModelScope.launch { repository.selectChannel(channelId) }
    }

    fun closeChannel() = repository.closeChannel()

    fun loadOlder(channelId: Int) {
        viewModelScope.launch { repository.loadOlder(channelId) }
    }

    fun sendMessage(channelId: Int, text: String, replyToMessageId: Int?) {
        viewModelScope.launch { repository.sendMessage(channelId, text, replyToMessageId) }
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

    fun startScreenShare(resultCode: Int, data: Intent?) {
        viewModelScope.launch { voiceEngine.startScreenShare(resultCode, data) }
    }

    fun stopScreenShare() {
        viewModelScope.launch { voiceEngine.stopScreenShare() }
    }

    fun hasChannelPermission(channelId: Int, permission: String) =
        repository.canUseChannelPermission(channelId, permission)

    fun refreshDirectMessages() {
        viewModelScope.launch { repository.refreshDirectMessages() }
    }

    override fun onCleared() {
        voiceEngine.release()
        repository.dispose()
        super.onCleared()
    }
}
