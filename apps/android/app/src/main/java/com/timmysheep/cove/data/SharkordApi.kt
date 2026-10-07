package com.timmysheep.cove.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class RpcException(
    message: String,
    val code: String = "UNKNOWN"
) : IOException(message)

class SharkordApi {
    private val http = OkHttpClient.Builder()
        .callTimeout(30, TimeUnit.SECONDS)
        .build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val nextId = AtomicInteger(1)
    private val pending = ConcurrentHashMap<Int, CompletableDeferred<JsonElement>>()
    private val subscriptions = ConcurrentHashMap<Int, Channel<JsonElement>>()
    private val disconnectEvents = MutableSharedFlow<Throwable>(extraBufferCapacity = 1)
    private var socket: WebSocket? = null
    private var keepAliveJob: Job? = null
    @Volatile private var uploadBaseUrl: HttpUrl? = null
    @Volatile private var authToken: String? = null
    @Volatile private var explicitlyClosed = false

    val disconnections = disconnectEvents.asSharedFlow()

    suspend fun serverInfo(baseUrl: HttpUrl): JsonElement = httpRequest(
        Request.Builder().url(baseUrl.newBuilder().addPathSegments("info").build()).get().build()
    )

    suspend fun login(baseUrl: HttpUrl, identity: String, password: String): LoginResponse {
        val body = buildJsonObject {
            put("identity", identity)
            put("password", password)
        }
        val request = Request.Builder()
            .url(baseUrl.newBuilder().addPathSegments("login").build())
            .post(jsonBody(body))
            .build()

        return httpRequest(request).decode<LoginResponse>()
    }

    suspend fun connect(baseUrl: HttpUrl, token: String) {
        explicitlyClosed = false
        uploadBaseUrl = baseUrl
        authToken = token
        val ready = CompletableDeferred<Unit>()
        val request = Request.Builder().url(webSocketRequestUrl(baseUrl)).build()

        socket = http.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                socket = webSocket
                val firstFrame = buildJsonObject {
                    put("method", "connectionParams")
                    putJsonObject("data") { put("token", token) }
                }
                if (!sendFrame(webSocket, firstFrame)) {
                    ready.completeExceptionally(RpcException("Unable to authenticate the connection"))
                    return
                }
                ready.complete(Unit)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                receiveFrame(webSocket, text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                ready.completeExceptionally(t)
                failPending(t)
                closeSubscriptions(t)
                if (!explicitlyClosed) disconnectEvents.tryEmit(t)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (!explicitlyClosed) {
                    val error = RpcException(reason.ifBlank { "The server closed the connection" }, "DISCONNECTED")
                    failPending(error)
                    closeSubscriptions(error)
                    disconnectEvents.tryEmit(error)
                }
            }
        })

        withTimeout(20_000) { ready.await() }
        keepAliveJob?.cancel()
        keepAliveJob = scope.launch {
            while (true) {
                delay(30_000)
                socket?.send("PING")
            }
        }
    }

    suspend fun query(path: String, input: JsonElement? = null): JsonElement = request("query", path, input)

    suspend fun mutate(path: String, input: JsonElement? = null): JsonElement = request("mutation", path, input)

    suspend fun upload(data: ByteArray, fileName: String, mimeType: String): TemporaryFile = withContext(Dispatchers.IO) {
        val baseUrl = uploadBaseUrl ?: throw RpcException("Not connected", "DISCONNECTED")
        val token = authToken ?: throw RpcException("Not connected", "DISCONNECTED")
        val encodedName = URLEncoder.encode(fileName.trim(), StandardCharsets.UTF_8.name()).replace("+", "%20")
        val request = Request.Builder()
            .url(baseUrl.newBuilder().addPathSegment("upload").build())
            .header("x-token", token)
            .header("x-file-name", encodedName)
            .header("x-file-type", mimeType)
            .post(data.toRequestBody("application/octet-stream".toMediaType()))
            .build()

        http.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val message = runCatching {
                    protocolJson.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.contentOrNull
                }.getOrNull()
                throw IOException(message ?: "Upload failed (${response.code})")
            }
            protocolJson.parseToJsonElement(body).decode<TemporaryFile>()
        }
    }

    fun publicFileUrl(file: MessageFile): String? {
        val baseUrl = uploadBaseUrl ?: return null
        val builder = baseUrl.newBuilder().addPathSegment("public").addPathSegment(file.name)
        if (file._accessToken != null && file._accessTokenExpiresAt != null) {
            builder.addQueryParameter("accessToken", file._accessToken)
            builder.addQueryParameter("expires", file._accessTokenExpiresAt.toString())
        }
        return builder.build().toString()
    }

    suspend fun downloadPublicFile(url: String): ByteArray = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(url).get().build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("File preview failed (${response.code})")
            response.body?.bytes() ?: throw IOException("File preview was empty")
        }
    }

    fun subscribe(path: String, input: JsonElement? = null): Flow<JsonElement> = callbackFlow {
        val id = nextId.getAndIncrement()
        val events = Channel<JsonElement>(Channel.BUFFERED)
        subscriptions[id] = events
        val forwardJob = launch {
            try {
                for (value in events) send(value)
            } finally {
                close()
            }
        }

        val params = buildJsonObject {
            put("path", path)
            input?.let { put("input", it) }
        }
        if (!sendFrame(buildJsonObject {
                put("id", id)
                put("method", "subscription")
                put("params", params)
            })) {
            close(RpcException("The connection is not open", "DISCONNECTED"))
        }

        awaitClose {
            subscriptions.remove(id)
            events.close()
            forwardJob.cancel()
            sendFrame(buildJsonObject {
                put("id", id)
                put("method", "subscription.stop")
            })
        }
    }

    fun close() {
        explicitlyClosed = true
        keepAliveJob?.cancel()
        keepAliveJob = null
        socket?.close(1000, "Client disconnected")
        socket = null
        uploadBaseUrl = null
        authToken = null
        failPending(RpcException("Connection closed", "DISCONNECTED"))
        closeSubscriptions(RpcException("Connection closed", "DISCONNECTED"))
    }

    private suspend fun request(method: String, path: String, input: JsonElement?): JsonElement {
        val id = nextId.getAndIncrement()
        val response = CompletableDeferred<JsonElement>()
        pending[id] = response
        val params = buildJsonObject {
            put("path", path)
            input?.let { put("input", it) }
        }
        val frame = buildJsonObject {
            put("id", id)
            put("method", method)
            put("params", params)
        }

        if (!sendFrame(frame)) {
            pending.remove(id)
            throw RpcException("The connection is not open", "DISCONNECTED")
        }

        return try {
            withTimeout(30_000) { response.await() }
        } finally {
            pending.remove(id)
        }
    }

    private fun receiveFrame(webSocket: WebSocket, text: String) {
        if (text == "PING") {
            webSocket.send("PONG")
            return
        }
        if (text == "PONG") return

        val decoded = try {
            protocolJson.parseToJsonElement(text)
        } catch (_: SerializationException) {
            return
        }

        if (decoded is JsonArray) {
            decoded.forEach(::handleResponse)
        } else {
            handleResponse(decoded)
        }
    }

    private fun handleResponse(frame: JsonElement) {
        val objectValue = frame as? JsonObject ?: return
        if (objectValue["method"]?.jsonPrimitive?.contentOrNull == "reconnect") {
            val error = RpcException("The server requested a reconnect", "RECONNECT")
            failPending(error)
            disconnectEvents.tryEmit(error)
            return
        }

        val id = objectValue["id"]?.jsonPrimitive?.intOrNull ?: return
        val errorValue = objectValue["error"] as? JsonObject
        if (errorValue != null) {
            val code = (errorValue["data"] as? JsonObject)?.get("code")?.jsonPrimitive?.contentOrNull ?: "UNKNOWN"
            val message = errorValue["message"]?.jsonPrimitive?.contentOrNull ?: "Request failed"
            val error = RpcException(message, code)
            pending.remove(id)?.completeExceptionally(error)
            subscriptions.remove(id)?.close(error)
            return
        }

        val result = objectValue["result"] as? JsonObject ?: return
        when (result["type"]?.jsonPrimitive?.contentOrNull ?: "data") {
            "data" -> {
                val data = result["data"] ?: JsonNull
                pending.remove(id)?.complete(data)
                subscriptions[id]?.trySend(data)
            }
            "stopped" -> subscriptions.remove(id)?.close()
            "started" -> Unit
        }
    }

    private suspend fun httpRequest(request: Request): JsonElement = withContext(Dispatchers.IO) {
        http.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val message = runCatching {
                    protocolJson.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.contentOrNull
                }.getOrNull()
                throw IOException(message ?: "Request failed (${response.code})")
            }
            protocolJson.parseToJsonElement(body)
        }
    }

    private fun sendFrame(value: JsonElement): Boolean {
        val current = socket ?: return false
        return sendFrame(current, value)
    }

    private fun sendFrame(webSocket: WebSocket, value: JsonElement): Boolean =
        webSocket.send(protocolJson.encodeToString(JsonElement.serializer(), value))

    private fun failPending(error: Throwable) {
        pending.values.forEach { it.completeExceptionally(error) }
        pending.clear()
    }

    private fun closeSubscriptions(error: Throwable) {
        subscriptions.values.forEach { it.close(error) }
        subscriptions.clear()
    }

    private fun jsonBody(value: JsonElement) = protocolJson
        .encodeToString(JsonElement.serializer(), value)
        .toRequestBody("application/json; charset=utf-8".toMediaType())

    companion object {
        val protocolJson = Json {
            ignoreUnknownKeys = true
            isLenient = true
            explicitNulls = false
            coerceInputValues = true
        }

        internal fun webSocketRequestUrl(baseUrl: HttpUrl): HttpUrl = baseUrl.newBuilder()
            .encodedPath("/")
            .query("connectionParams=1")
            .build()
    }
}

inline fun <reified T> JsonElement.decode(): T = SharkordApi.protocolJson.decodeFromJsonElement(this)
