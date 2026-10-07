package com.timmysheep.cove.data

import androidx.core.text.htmlEncode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.IOException

class CoveRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutableState = MutableStateFlow(SessionState())
    private var api: SharkordApi? = null
    private val subscriptions = mutableListOf<Job>()
    private var disconnectJob: Job? = null
    private var reconnectJob: Job? = null
    private var credentials: Credentials? = null
    private var reconnectAttempt = 0

    val state: StateFlow<SessionState> = mutableState.asStateFlow()

    suspend fun connect(host: String, identity: String, password: String, serverPassword: String) {
        val normalized = normalizeServerAddress(host)
        if (normalized == null) {
            mutableState.value = mutableState.value.copy(
                connecting = false,
                error = "Enter a valid server address"
            )
            return
        }

        val savedCredentials = Credentials(normalized.toString(), identity.trim(), password, serverPassword)
        credentials = savedCredentials
        reconnectAttempt = 0
        reconnectJob?.cancel()
        connectInternal(savedCredentials, showLoading = true)
    }

    fun disconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
        disconnectJob?.cancel()
        subscriptions.forEach(Job::cancel)
        subscriptions.clear()
        api?.close()
        api = null
        credentials = null
        mutableState.value = SessionState()
    }

    fun dispose() {
        disconnect()
        scope.coroutineContext[Job]?.cancel()
    }

    fun clearError() {
        mutableState.value = mutableState.value.copy(error = null)
    }

    suspend fun selectChannel(channelId: Int) {
        mutableState.value = mutableState.value.copy(activeChannelId = channelId, error = null)
        if (mutableState.value.messagesByChannel[channelId].isNullOrEmpty()) {
            loadMessages(channelId)
        }
        markAsRead(channelId)
    }

    fun closeChannel() {
        mutableState.value = mutableState.value.copy(activeChannelId = null)
    }

    suspend fun loadOlder(channelId: Int) {
        val cursor = mutableState.value.messageCursors[channelId] ?: return
        runCatching {
            currentApi().query("messages.get", buildJsonObject {
                put("channelId", channelId)
                put("limit", 50)
                putJsonObject("cursor") {
                    put("createdAt", cursor.createdAt)
                    put("id", cursor.id)
                }
            }).decode<MessagesPage>()
        }.onSuccess { page ->
            val existing = mutableState.value.messagesByChannel[channelId].orEmpty()
            val knownIds = existing.mapTo(mutableSetOf()) { it.id }
            val older = page.messages.filterNot { it.id in knownIds }
                .sortedWith(compareBy<Message> { it.createdAt }.thenBy { it.id })
            updateState { current ->
                current.copy(
                    messagesByChannel = current.messagesByChannel + (channelId to (older + existing)),
                    messageCursors = current.messageCursors + (channelId to page.nextCursor)
                )
            }
        }.onFailure { reportError(it) }
    }

    suspend fun sendMessage(channelId: Int, text: String, replyToMessageId: Int?) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val escaped = trimmed.htmlEncode().replace("\n", "<br class=\"hard-break\">")
        runCatching {
            currentApi().mutate("messages.send", buildJsonObject {
                put("channelId", channelId)
                put("content", "<p>$escaped</p>")
                put("files", JsonArray(emptyList()))
                replyToMessageId?.let { put("replyToMessageId", it) }
            })
        }.onFailure { reportError(it) }
    }

    suspend fun editMessage(messageId: Int, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val escaped = trimmed.htmlEncode().replace("\n", "<br class=\"hard-break\">")
        runCatching {
            currentApi().mutate("messages.edit", buildJsonObject {
                put("messageId", messageId)
                put("content", "<p>$escaped</p>")
            })
        }.onFailure { reportError(it) }
    }

    suspend fun deleteMessage(messageId: Int) {
        runCatching {
            currentApi().mutate("messages.delete", buildJsonObject { put("messageId", messageId) })
        }.onFailure { reportError(it) }
    }

    suspend fun togglePin(messageId: Int) {
        runCatching {
            currentApi().mutate("messages.togglePin", buildJsonObject { put("messageId", messageId) })
        }.onFailure { reportError(it) }
    }

    suspend fun toggleReaction(messageId: Int, emoji: String) {
        runCatching {
            currentApi().mutate("messages.toggleReaction", buildJsonObject {
                put("messageId", messageId)
                put("emoji", emoji)
            })
        }.onFailure { reportError(it) }
    }

    fun signalTyping(channelId: Int) {
        scope.launch {
            runCatching {
                currentApi().mutate("messages.signalTyping", buildJsonObject { put("channelId", channelId) })
            }
        }
    }

    suspend fun openDirectMessage(userId: Int) {
        runCatching {
            val result = currentApi().mutate("dms.open", buildJsonObject { put("userId", userId) })
                .decode<OpenDirectMessageResponse>()
            loadDirectMessages()
            selectChannel(result.channelId)
        }.onFailure { reportError(it) }
    }

    suspend fun refreshDirectMessages() {
        runCatching { loadDirectMessages() }.onFailure { reportError(it) }
    }

    suspend fun joinVoice(channelId: Int): JsonObject {
        val result = currentApi().mutate("voice.join", buildJsonObject {
                put("channelId", channelId)
                putJsonObject("state") {
                    put("micMuted", true)
                    put("soundMuted", false)
                }
            })
        val routerCapabilities = result.jsonObject["routerRtpCapabilities"]?.jsonObject
            ?: throw RpcException("The server did not return voice capabilities", "BAD_RESPONSE")
        updateState {
            it.copy(
                voiceChannelId = channelId,
                microphoneEnabled = false,
                speakerEnabled = true,
                sharingScreen = false,
                consumedRemoteStreams = emptySet()
            )
        }
        return routerCapabilities
    }

    suspend fun leaveVoice() {
        try {
            currentApi().mutate("voice.leave")
        } catch (error: Throwable) {
            reportError(error)
        } finally {
            updateState {
                it.copy(
                    voiceChannelId = null,
                    microphoneEnabled = false,
                    speakerEnabled = true,
                    sharingScreen = false,
                    consumedRemoteStreams = emptySet()
                )
            }
        }
    }

    suspend fun updateVoiceState(
        micMuted: Boolean? = null,
        soundMuted: Boolean? = null,
        sharingScreen: Boolean? = null
    ) {
        currentApi().mutate("voice.updateState", buildJsonObject {
            micMuted?.let { put("micMuted", it) }
            soundMuted?.let { put("soundMuted", it) }
            sharingScreen?.let { put("sharingScreen", it) }
        })
    }

    suspend fun createProducerTransport(): VoiceTransportParams =
        currentApi().mutate("voice.createProducerTransport").decode()

    suspend fun createConsumerTransport(): VoiceTransportParams =
        currentApi().mutate("voice.createConsumerTransport").decode()

    suspend fun connectProducerTransport(dtlsParameters: JsonObject) {
        currentApi().mutate("voice.connectProducerTransport", buildJsonObject {
            put("dtlsParameters", dtlsParameters)
        })
    }

    suspend fun connectConsumerTransport(dtlsParameters: JsonObject) {
        currentApi().mutate("voice.connectConsumerTransport", buildJsonObject {
            put("dtlsParameters", dtlsParameters)
        })
    }

    suspend fun produceVoice(transportId: String, kind: String, rtpParameters: JsonObject): String =
        currentApi().mutate("voice.produce", buildJsonObject {
            put("transportId", transportId)
            put("kind", kind)
            put("rtpParameters", rtpParameters)
        }).jsonPrimitive.contentOrNull ?: throw RpcException("The server did not return a producer id", "BAD_RESPONSE")

    suspend fun consumeVoice(kind: String, remoteId: Int, rtpCapabilities: JsonObject): ConsumeResult =
        currentApi().mutate("voice.consume", buildJsonObject {
            put("kind", kind)
            put("remoteId", remoteId)
            put("rtpCapabilities", rtpCapabilities)
        }).decode()

    suspend fun getVoiceProducers(): RemoteProducerIds = currentApi().query("voice.getProducers").decode()

    suspend fun closeVoiceProducer(kind: String) {
        currentApi().mutate("voice.closeProducer", buildJsonObject { put("kind", kind) })
    }

    fun voiceProducerEvents() = currentApi().subscribe("voice.onNewProducer").mapNotNull { decodeOrNull<VoiceProducerEvent>(it) }

    fun voiceProducerClosedEvents() = currentApi().subscribe("voice.onProducerClosed").mapNotNull { decodeOrNull<VoiceProducerEvent>(it) }

    fun updateVoiceMediaState(
        microphoneEnabled: Boolean? = null,
        speakerEnabled: Boolean? = null,
        sharingScreen: Boolean? = null,
        consumedRemoteStreams: Set<String>? = null
    ) {
        updateState { current ->
            current.copy(
                microphoneEnabled = microphoneEnabled ?: current.microphoneEnabled,
                speakerEnabled = speakerEnabled ?: current.speakerEnabled,
                sharingScreen = sharingScreen ?: current.sharingScreen,
                consumedRemoteStreams = consumedRemoteStreams ?: current.consumedRemoteStreams
            )
        }
    }

    fun canUseChannelPermission(channelId: Int, permission: String): Boolean =
        hasChannelPermission(channelId, permission)

    fun setError(message: String) {
        mutableState.value = mutableState.value.copy(error = message)
    }

    private suspend fun connectInternal(credentials: Credentials, showLoading: Boolean) {
        if (showLoading) mutableState.value = SessionState(connecting = true, serverAddress = credentials.host)
        var candidate: SharkordApi? = null
        try {
            val baseUrl = credentials.host.toHttpUrlOrNull() ?: throw IOException("Enter a valid server address")
            val client = SharkordApi()
            candidate = client
            client.serverInfo(baseUrl)
            val login = client.login(baseUrl, credentials.identity, credentials.password)
            client.connect(baseUrl, login.token)
            val handshake = client.query("others.handshake").decode<Handshake>()
            val joinInput = buildJsonObject {
                put("handshakeHash", handshake.handshakeHash)
                if (handshake.hasPassword && credentials.serverPassword.isNotBlank()) {
                    put("password", credentials.serverPassword)
                }
            }
            val joined = client.query("others.joinServer", joinInput).decode<JoinResponse>()
            api?.close()
            api = client
            mutableState.value = SessionState(
                connected = true,
                serverAddress = credentials.host,
                serverName = joined.serverName,
                ownUserId = joined.ownUserId,
                categories = joined.categories.sortedBy(Category::position),
                channels = joined.channels,
                users = joined.users.sortedBy { it.name.lowercase() },
                voiceUsersByChannel = parseVoiceMap(joined.voiceMap),
                unreadByChannel = joined.readStates.mapNotNull { (key, value) ->
                    key.toIntOrNull()?.let { channelId -> channelId to (value.jsonPrimitive.intOrNull ?: 0) }
                }.toMap(),
                channelPermissions = joined.channelPermissions,
                publicSettings = joined.publicSettings,
                activeChannelId = joined.channels.firstOrNull { it.type == ChannelType.TEXT && !it.isDm }?.id
            )
            startSubscriptions(client)
            listenForDisconnect(client)
            mutableState.value.activeChannelId?.let { selectChannel(it) }
            try {
                loadDirectMessages()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                reportError(error)
            }
            reconnectAttempt = 0
        } catch (error: Throwable) {
            candidate?.close()
            if (error is CancellationException) throw error
            if (api === candidate) api = null
            mutableState.value = mutableState.value.copy(
                connecting = false,
                connected = false,
                error = error.message ?: "Unable to connect"
            )
        }
    }

    private fun startSubscriptions(client: SharkordApi) {
        subscriptions.forEach(Job::cancel)
        subscriptions.clear()
        observe(client, "messages.onNew", ::applyMessage)
        observe(client, "messages.onUpdate", ::applyMessage)
        observe(client, "messages.onDelete") { value ->
            val event = decodeOrNull<MessageDeleteEvent>(value) ?: return@observe
            updateState { current ->
                val existing = current.messagesByChannel[event.channelId].orEmpty()
                current.copy(messagesByChannel = current.messagesByChannel + (
                    event.channelId to existing.filterNot { it.id == event.messageId }
                ))
            }
        }
        observe(client, "channels.onCreate", ::applyChannel)
        observe(client, "channels.onUpdate", ::applyChannel)
        observe(client, "channels.onDelete") { value ->
            val id = value.jsonPrimitive.intOrNull ?: return@observe
            updateState { it.copy(channels = it.channels.filterNot { channel -> channel.id == id }) }
        }
        observe(client, "categories.onCreate", ::applyCategory)
        observe(client, "categories.onUpdate", ::applyCategory)
        observe(client, "categories.onDelete") { value ->
            val id = value.jsonPrimitive.intOrNull ?: return@observe
            updateState { it.copy(categories = it.categories.filterNot { category -> category.id == id }) }
        }
        observe(client, "users.onJoin", ::applyUser)
        observe(client, "users.onCreate", ::applyUser)
        observe(client, "users.onUpdate", ::applyUser)
        observe(client, "users.onLeave") { value ->
            val id = value.jsonPrimitive.intOrNull
                ?: (value as? JsonObject)?.get("id")?.jsonPrimitive?.intOrNull
                ?: return@observe
            updateState { current ->
                current.copy(users = current.users.map { user -> if (user.id == id) user.copy(status = "offline") else user })
            }
        }
        observe(client, "voice.onJoin", ::applyVoiceJoin)
        observe(client, "voice.onUpdateState", ::applyVoiceJoin)
        observe(client, "voice.onLeave", ::applyVoiceLeave)
        observe(client, "dms.onConversationOpen") { refreshDirectMessages() }
        observe(client, "channels.onReadStateUpdate") { value ->
            val event = value as? JsonObject ?: return@observe
            val id = event["channelId"]?.jsonPrimitive?.intOrNull ?: return@observe
            val count = event["count"]?.jsonPrimitive?.intOrNull ?: 0
            updateState { it.copy(unreadByChannel = it.unreadByChannel + (id to count)) }
        }
    }

    private fun listenForDisconnect(client: SharkordApi) {
        disconnectJob?.cancel()
        disconnectJob = scope.launch {
            client.disconnections.collect { error ->
                if (api !== client || credentials == null) return@collect
                updateState { it.copy(connected = false, error = error.message ?: "Connection lost") }
                scheduleReconnect()
            }
        }
    }

    private fun scheduleReconnect() {
        if (reconnectJob?.isActive == true) return
        reconnectJob = scope.launch {
            val delays = listOf(1L, 2L, 4L, 8L, 8L)
            while (reconnectAttempt < delays.size) {
                delay(delays[reconnectAttempt] * 1_000)
                reconnectAttempt += 1
                val saved = credentials ?: return@launch
                connectInternal(saved, showLoading = false)
                if (mutableState.value.connected) return@launch
            }
            updateState { it.copy(error = "Connection lost. Reconnect manually.") }
        }
    }

    private fun observe(client: SharkordApi, path: String, handler: suspend (JsonElement) -> Unit) {
        subscriptions += scope.launch {
            client.subscribe(path)
                .catch { error -> reportError(error) }
                .collect { value -> if (api === client) handler(value) }
        }
    }

    private suspend fun loadMessages(channelId: Int) {
        runCatching {
            currentApi().query("messages.get", buildJsonObject {
                put("channelId", channelId)
                put("limit", 50)
            }).decode<MessagesPage>()
        }.onSuccess { page ->
            val messages = page.messages.sortedWith(compareBy<Message> { it.createdAt }.thenBy { it.id })
            updateState { current ->
                current.copy(
                    messagesByChannel = current.messagesByChannel + (channelId to messages),
                    messageCursors = current.messageCursors + (channelId to page.nextCursor)
                )
            }
        }.onFailure { reportError(it) }
    }

    private suspend fun loadDirectMessages() {
        val values = currentApi().query("dms.get").decode<List<DirectMessageConversation>>()
        updateState { it.copy(conversations = values.sortedByDescending(DirectMessageConversation::lastMessageAt)) }
    }

    private suspend fun markAsRead(channelId: Int) {
        runCatching {
            currentApi().mutate("channels.markAsRead", buildJsonObject { put("channelId", channelId) })
        }.onFailure { reportError(it) }
    }

    private fun applyMessage(value: JsonElement) {
        val message = decodeOrNull<Message>(value) ?: return
        updateState { current ->
            val existing = current.messagesByChannel[message.channelId].orEmpty()
            val replaced = existing.filterNot { it.id == message.id } + message
            current.copy(messagesByChannel = current.messagesByChannel + (
                message.channelId to replaced.sortedWith(compareBy<Message> { it.createdAt }.thenBy { it.id })
            ))
        }
    }

    private fun applyChannel(value: JsonElement) {
        val channel = decodeOrNull<Channel>(value) ?: return
        updateState { current ->
            current.copy(channels = (current.channels.filterNot { it.id == channel.id } + channel).sortedBy(Channel::position))
        }
    }

    private fun applyCategory(value: JsonElement) {
        val category = decodeOrNull<Category>(value) ?: return
        updateState { current ->
            current.copy(categories = (current.categories.filterNot { it.id == category.id } + category).sortedBy(Category::position))
        }
    }

    private fun applyUser(value: JsonElement) {
        val user = decodeOrNull<User>(value) ?: return
        updateState { current ->
            current.copy(users = (current.users.filterNot { it.id == user.id } + user).sortedBy { it.name.lowercase() })
        }
    }

    private fun applyVoiceJoin(value: JsonElement) {
        val event = decodeOrNull<VoiceJoinEvent>(value) ?: return
        val voiceState = event.state ?: return
        updateState { current ->
            val users = current.voiceUsersByChannel[event.channelId].orEmpty() + (event.userId to voiceState)
            current.copy(voiceUsersByChannel = current.voiceUsersByChannel + (event.channelId to users))
        }
    }

    private fun applyVoiceLeave(value: JsonElement) {
        val event = decodeOrNull<VoiceLeaveEvent>(value) ?: return
        updateState { current ->
            val users = current.voiceUsersByChannel[event.channelId].orEmpty() - event.userId
            current.copy(voiceUsersByChannel = current.voiceUsersByChannel + (event.channelId to users))
        }
    }

    private fun hasChannelPermission(channelId: Int, permission: String): Boolean {
        val current = mutableState.value
        if (current.channels.firstOrNull { it.id == channelId }?.isDm == true) return true
        val permissions = current.channelPermissions[channelId.toString()]
            ?.jsonObject?.get("permissions")?.jsonObject
        return permissions?.get(permission)?.jsonPrimitive?.booleanOrNull ?: false
    }

    private fun parseVoiceMap(raw: JsonObject): Map<Int, Map<Int, VoiceUserState>> =
        raw.mapNotNull { (channelId, channelValue) ->
            val users = (channelValue as? JsonObject)?.get("users") as? JsonObject ?: return@mapNotNull null
            val parsedUsers = users.mapNotNull { (userId, state) ->
                val id = userId.toIntOrNull() ?: return@mapNotNull null
                val voiceState = decodeOrNull<VoiceUserState>(state) ?: return@mapNotNull null
                id to voiceState
            }.toMap()
            channelId.toIntOrNull()?.let { it to parsedUsers }
        }.toMap()

    private fun currentApi(): SharkordApi = api ?: throw RpcException("Not connected", "DISCONNECTED")

    private fun reportError(error: Throwable) {
        updateState { it.copy(error = error.message ?: "Something went wrong") }
    }

    private fun updateState(transform: (SessionState) -> SessionState) {
        mutableState.value = transform(mutableState.value)
    }

    private inline fun <reified T> decodeOrNull(value: JsonElement): T? =
        runCatching { value.decode<T>() }.getOrNull()

    private fun normalizeServerAddress(value: String): HttpUrl? {
        val trimmed = value.trim().trimEnd('/')
        if (trimmed.isEmpty()) return null
        val withScheme = if (trimmed.contains("://")) trimmed else "https://$trimmed"
        return withScheme.toHttpUrlOrNull()?.takeIf { it.scheme == "https" || it.scheme == "http" }
    }

    private data class Credentials(
        val host: String,
        val identity: String,
        val password: String,
        val serverPassword: String
    )
}
