package com.timmysheep.cove.voice

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import com.timmysheep.cove.R
import com.timmysheep.cove.data.AppDiagnosticsLog
import com.timmysheep.cove.data.CoveRepository
import com.timmysheep.cove.data.VoiceConnectionStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.mediasoup.droid.Consumer
import org.mediasoup.droid.Device
import org.mediasoup.droid.MediasoupClient
import org.mediasoup.droid.PeerConnection
import org.mediasoup.droid.Producer
import org.mediasoup.droid.RecvTransport
import org.mediasoup.droid.SendTransport
import org.mediasoup.droid.Transport
import org.webrtc.Camera1Enumerator
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraEnumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.MediaConstraints
import org.webrtc.PeerConnectionFactory
import org.webrtc.ScreenCapturerAndroid
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import org.webrtc.audio.AudioDeviceModule
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.atomic.AtomicBoolean

data class RemoteVideoTrack(
    val key: String,
    val remoteId: Int,
    val kind: String,
    val track: VideoTrack,
    val qualityLayers: List<com.timmysheep.cove.data.VoiceQualityLayer> = emptyList()
)

class CoveVoiceEngine(
    context: Context,
    private val repository: CoveRepository
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val producerMutex = Mutex()
    private val cameraMutex = Mutex()
    private val screenShareMutex = Mutex()
    private val mutableVideoTracks = MutableStateFlow<List<RemoteVideoTrack>>(emptyList())
    private val mutableLocalCameraTrack = MutableStateFlow<VideoTrack?>(null)
    private val mutableEglBaseContext = MutableStateFlow<EglBase.Context?>(null)
    private val mutableActiveSpeakerIds = MutableStateFlow<Set<Int>>(emptySet())
    private val consumers = mutableMapOf<String, Consumer>()
    private val consumerEvents = mutableListOf<Job>()
    private var audioLevelPollingJob: Job? = null
    private val producerTransportConnected = AtomicBoolean(false)
    private val consumerTransportConnected = AtomicBoolean(false)
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var device: Device? = null
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var audioDeviceModule: AudioDeviceModule? = null
    private var sendTransport: SendTransport? = null
    private var recvTransport: RecvTransport? = null
    private var microphoneSource: AudioSource? = null
    private var microphoneTrack: AudioTrack? = null
    private var microphoneProducer: Producer? = null
    private var screenCapturer: ScreenCapturerAndroid? = null
    private var screenSource: VideoSource? = null
    private var screenTrack: VideoTrack? = null
    private var screenProducer: Producer? = null
    private var cameraCapturer: CameraVideoCapturer? = null
    private var cameraSource: VideoSource? = null
    private var cameraTrack: VideoTrack? = null
    private var cameraProducer: Producer? = null
    private var cameraTextureHelper: SurfaceTextureHelper? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null
    private var eglBase: EglBase? = null
    private var microphoneWasEnabledBeforeDeafen = false

    val remoteVideoTracks: StateFlow<List<RemoteVideoTrack>> = mutableVideoTracks.asStateFlow()
    val localCameraTrack: StateFlow<VideoTrack?> = mutableLocalCameraTrack.asStateFlow()
    val eglBaseContext: StateFlow<EglBase.Context?> = mutableEglBaseContext.asStateFlow()
    val activeSpeakerIds: StateFlow<Set<Int>> = mutableActiveSpeakerIds.asStateFlow()

    private data class AudioLevelSources(
        val localUserId: Int?,
        val microphoneProducer: Producer?,
        val remoteAudioConsumers: List<Pair<Int, Consumer>>
    )

    init {
        scope.launch {
            repository.state
                .map { VoiceCallNotificationSnapshot.from(it) }
                .distinctUntilChanged()
                .collect { snapshot ->
                    if (snapshot == null) {
                        VoiceCallService.cancelNotification(appContext)
                    } else {
                        VoiceCallService.updateNotification(appContext, snapshot)
                    }
                }
        }
    }

    suspend fun join(channelId: Int, microphoneEnabledOnJoin: Boolean = false) {
        if (repository.state.value.voiceChannelId == channelId && device != null) return
        if (repository.state.value.voiceChannelId != null) leave()

        try {
            repository.setVoiceConnectionStatus(VoiceConnectionStatus.CONNECTING, channelId)
            val routerCapabilities = repository.joinVoice(channelId)
            initializeMediasoup(routerCapabilities)
            val connectionOptions = PeerConnection.Options().apply {
                setFactory(requireNotNull(peerConnectionFactory))
            }
            val mediasoupDevice = Device()
            mediasoupDevice.load(routerCapabilities.toString(), connectionOptions)
            device = mediasoupDevice

            val sendParams = repository.createProducerTransport()
            sendTransport = mediasoupDevice.createSendTransport(
                sendListener,
                sendParams.id,
                sendParams.iceParameters.toString(),
                sendParams.iceCandidates.toString(),
                sendParams.dtlsParameters.toString(),
                null,
                connectionOptions,
                "{}"
            )

            val receiveParams = repository.createConsumerTransport()
            recvTransport = mediasoupDevice.createRecvTransport(
                receiveListener,
                receiveParams.id,
                receiveParams.iceParameters.toString(),
                receiveParams.iceCandidates.toString(),
                receiveParams.dtlsParameters.toString(),
                null,
                connectionOptions,
                "{}"
            )

            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            setSpeakerphoneEnabled(true)
            startCallService()
            repository.updateVoiceMediaState(microphoneEnabled = false, speakerEnabled = true)
            startProducerObservers(channelId)
            reconcileProducers(channelId)
            if (microphoneEnabledOnJoin) setMicrophoneEnabled(true)
            repository.setVoiceConnectionStatus(VoiceConnectionStatus.CONNECTED)
            startAudioLevelPolling()
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            closeMediaObjects()
            runCatching { repository.leaveVoice() }
            repository.setError(error.message ?: appContext.getString(R.string.voice_join_failed), error)
        }
    }

    suspend fun leave() = screenShareMutex.withLock {
        cameraMutex.withLock {
            stopProducerObservers()
            if (screenProducer != null) runCatching { repository.closeVoiceProducer("screen") }
            if (cameraProducer != null) runCatching { repository.closeVoiceProducer("video") }
            closeMediaObjects()
            audioManager.mode = AudioManager.MODE_NORMAL
            stopVoiceService()
            runCatching { repository.leaveVoice() }
        }
    }

    suspend fun setMicrophoneEnabled(enabled: Boolean) {
        if (repository.state.value.voiceChannelId == null) return
        val currentState = repository.state.value
        if (enabled && !currentState.speakerEnabled) {
            repository.setError(appContext.getString(R.string.speaker_output_required))
            return
        }

        if (!enabled) {
            microphoneTrack?.setEnabled(false)
            runCatching { repository.updateVoiceState(micMuted = true) }
                .onSuccess { repository.updateVoiceMediaState(microphoneEnabled = false) }
                .onFailure { repository.setError(it.message ?: appContext.getString(R.string.microphone_mute_failed), it) }
            syncVoiceService()
            return
        }

        if (appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            repository.setError(appContext.getString(R.string.microphone_permission_required))
            return
        }

        try {
            when {
                screenCapturer != null -> startScreenService()
                cameraCapturer != null -> startCameraService()
                else -> startVoiceService()
            }
            val transport = requireNotNull(sendTransport)
            val track = microphoneTrack ?: createMicrophoneTrack().also { microphoneTrack = it }
            track.setEnabled(false)
            if (microphoneProducer == null) {
                microphoneProducer = producerMutex.withLock {
                    transport.produce(producerListener, track, null, null, null, """{"kind":"audio"}""")
                }
            }
            track.setEnabled(true)
            repository.updateVoiceState(micMuted = false)
            repository.updateVoiceMediaState(microphoneEnabled = true)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            microphoneTrack?.setEnabled(false)
            repository.setError(error.message ?: appContext.getString(R.string.microphone_enable_failed), error)
        }
    }

    suspend fun setSpeakerEnabled(enabled: Boolean) {
        if (repository.state.value.voiceChannelId == null) return
        val currentlyEnabled = repository.state.value.speakerEnabled
        if (currentlyEnabled == enabled) return

        try {
            val restoreMicrophone = enabled && microphoneWasEnabledBeforeDeafen
            if (!enabled) {
                microphoneWasEnabledBeforeDeafen = repository.state.value.microphoneEnabled
                microphoneTrack?.setEnabled(false)
                consumers.values.forEach { if (it.kind == "audio") it.track?.setEnabled(false) }
                repository.updateVoiceState(micMuted = true, soundMuted = true)
                repository.updateVoiceMediaState(microphoneEnabled = false, speakerEnabled = false)
                syncVoiceService()
                setSpeakerphoneEnabled(false)
            } else {
                when {
                    screenCapturer != null -> startScreenService()
                    cameraCapturer != null -> startCameraService()
                    else -> startCallService()
                }
                setSpeakerphoneEnabled(true)
                consumers.values.forEach { if (it.kind == "audio") it.track?.setEnabled(true) }
                repository.updateVoiceState(soundMuted = false)
                repository.updateVoiceMediaState(speakerEnabled = true)
                if (restoreMicrophone) {
                    microphoneWasEnabledBeforeDeafen = false
                    setMicrophoneEnabled(true)
                }
            }
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            repository.setError(error.message ?: appContext.getString(R.string.speaker_update_failed), error)
        }
    }

    suspend fun setCameraEnabled(enabled: Boolean) = cameraMutex.withLock {
        val channelId = repository.state.value.voiceChannelId ?: return@withLock
        if (repository.state.value.cameraEnabled == enabled) return@withLock

        if (!enabled) {
            cameraTrack?.setEnabled(false)
            cameraProducer?.close()
            cameraProducer = null
            stopCameraCapture()
            runCatching { repository.closeVoiceProducer("video") }
            runCatching { repository.updateVoiceState(webcamEnabled = false) }
            repository.updateVoiceMediaState(cameraEnabled = false)
            syncVoiceService()
            return@withLock
        }

        if (!repository.canUseServerPermission("ENABLE_WEBCAM") ||
            !repository.canUseChannelPermission(channelId, "WEBCAM")
        ) {
            repository.setError(appContext.getString(R.string.camera_permission_required))
            return
        }
        if (appContext.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            repository.setError(appContext.getString(R.string.camera_permission_denied))
            return
        }

        try {
            startCameraService()
            val factory = requireNotNull(peerConnectionFactory)
            val transport = requireNotNull(sendTransport)
            val base = getOrCreateEglBase()
            val textureHelper = SurfaceTextureHelper.create("CoveCameraCapture", base.eglBaseContext)
            cameraTextureHelper = textureHelper

            val enumerator: CameraEnumerator = if (Camera2Enumerator.isSupported(appContext)) {
                Camera2Enumerator(appContext)
            } else {
                Camera1Enumerator(true)
            }
            val deviceNames = enumerator.deviceNames
            val cameraName = deviceNames.firstOrNull(enumerator::isFrontFacing)
                ?: deviceNames.firstOrNull()
                ?: throw IllegalStateException(appContext.getString(R.string.camera_unavailable))
            val capturer = enumerator.createCapturer(cameraName, null)
                ?: throw IllegalStateException(appContext.getString(R.string.camera_unavailable))
            cameraCapturer = capturer

            val source = factory.createVideoSource(false)
            cameraSource = source
            capturer.initialize(textureHelper, appContext, source.capturerObserver)
            capturer.startCapture(640, 480, 24)

            val track = factory.createVideoTrack("video-$channelId", source)
            cameraTrack = track
            track.setEnabled(true)
            cameraProducer = producerMutex.withLock {
                transport.produce(producerListener, track, null, null, null, """{"kind":"video"}""")
            }
            repository.updateVoiceState(webcamEnabled = true)
            repository.updateVoiceMediaState(cameraEnabled = true)
            mutableLocalCameraTrack.value = track
        } catch (error: Throwable) {
            cameraProducer?.close()
            cameraProducer = null
            stopCameraCapture()
            runCatching { repository.closeVoiceProducer("video") }
            runCatching { repository.updateVoiceState(webcamEnabled = false) }
            repository.updateVoiceMediaState(cameraEnabled = false)
            syncVoiceService()
            if (error is CancellationException) throw error
            repository.setError(error.message ?: appContext.getString(R.string.camera_start_failed), error)
        }
    }

    fun switchCamera() {
        val capturer = cameraCapturer ?: return
        capturer.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
            override fun onCameraSwitchDone(isFrontCamera: Boolean) = Unit

            override fun onCameraSwitchError(errorDescription: String) {
                repository.setError(errorDescription)
            }
        })
    }

    suspend fun startScreenShare(resultCode: Int, resultData: Intent?) = screenShareMutex.withLock {
        val channelId = repository.state.value.voiceChannelId ?: return@withLock
        if (resultCode != Activity.RESULT_OK || resultData == null) return@withLock
        if (screenCapturer != null || screenProducer != null) return@withLock

        AppDiagnosticsLog.info("voice", "screen share start requested channel=$channelId")
        try {
            // server authorization is authoritative; local permission snapshots can be stale.
            startScreenService()
            val factory = requireNotNull(peerConnectionFactory)
            val transport = requireNotNull(sendTransport)
            val base = getOrCreateEglBase()
            val textureHelper = SurfaceTextureHelper.create("CoveScreenCapture", base.eglBaseContext)
            surfaceTextureHelper = textureHelper
            val source = factory.createVideoSource(false)
            screenSource = source
            val capturer = ScreenCapturerAndroid(resultData, object : MediaProjection.Callback() {
                override fun onStop() {
                    scope.launch { stopScreenShare() }
                }
            })
            screenCapturer = capturer
            capturer.initialize(textureHelper, appContext, source.capturerObserver)
            capturer.startCapture(1280, 720, 15)
            val track = factory.createVideoTrack("screen-$channelId", source)
            track.setEnabled(true)
            screenTrack = track
            screenProducer = producerMutex.withLock {
                transport.produce(producerListener, track, null, null, null, """{"kind":"screen"}""")
            }
            repository.updateVoiceState(sharingScreen = true)
            repository.updateVoiceMediaState(sharingScreen = true)
            AppDiagnosticsLog.info("voice", "screen share started channel=$channelId")
        } catch (error: Throwable) {
            screenProducer?.close()
            screenProducer = null
            stopScreenCapture()
            runCatching { repository.closeVoiceProducer("screen") }
            runCatching { repository.updateVoiceState(sharingScreen = false) }
            repository.updateVoiceMediaState(sharingScreen = false)
            syncVoiceService()
            if (error is CancellationException) throw error
            repository.setError(error.message ?: appContext.getString(R.string.screen_share_failed), error)
        }
    }

    suspend fun stopScreenShare() = screenShareMutex.withLock {
        if (screenProducer == null && screenCapturer == null && !repository.state.value.sharingScreen) {
            return@withLock
        }
        AppDiagnosticsLog.info("voice", "screen share stop requested")
        screenProducer?.close()
        screenProducer = null
        stopScreenCapture()
        runCatching { repository.closeVoiceProducer("screen") }
        runCatching { repository.updateVoiceState(sharingScreen = false) }
        repository.updateVoiceMediaState(sharingScreen = false)
        syncVoiceService()
    }

    fun release() {
        stopProducerObservers()
        closeMediaObjects()
        eglBase?.release()
        eglBase = null
        mutableEglBaseContext.value = null
        stopVoiceService()
        scope.cancel()
    }

    private fun initializeMediasoup(routerCapabilities: JsonObject) {
        if (!mediasoupInitialized) {
            MediasoupClient.initialize(appContext)
            mediasoupInitialized = true
        }
        initializePeerConnectionFactory(appContext)
        val base = getOrCreateEglBase()
        audioDeviceModule = JavaAudioDeviceModule.builder(appContext).createAudioDeviceModule()
        peerConnectionFactory = PeerConnectionFactory.builder()
            .setOptions(PeerConnectionFactory.Options())
            .setAudioDeviceModule(requireNotNull(audioDeviceModule))
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(base.eglBaseContext, true, true))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(base.eglBaseContext))
            .createPeerConnectionFactory()
        if (routerCapabilities.isEmpty()) throw IllegalStateException("The voice router returned no capabilities")
    }

    private fun createMicrophoneTrack(): AudioTrack {
        val factory = requireNotNull(peerConnectionFactory)
        val source = factory.createAudioSource(MediaConstraints())
        microphoneSource = source
        return factory.createAudioTrack("microphone", source).also { it.setEnabled(false) }
    }

    private fun startProducerObservers(channelId: Int) {
        stopProducerObservers()
        consumerEvents += scope.launch {
            repository.voiceProducerEvents().collect { event ->
                if (event.channelId == channelId && event.remoteId != repository.state.value.ownUserId) {
                    consume(event.remoteId, event.kind)
                }
            }
        }
        consumerEvents += scope.launch {
            repository.voiceProducerClosedEvents().collect { event ->
                if (event.channelId == channelId) closeConsumer(event.remoteId, event.kind)
            }
        }
    }

    private fun stopProducerObservers() {
        consumerEvents.forEach(Job::cancel)
        consumerEvents.clear()
    }

    private fun startAudioLevelPolling() {
        audioLevelPollingJob?.cancel()
        audioLevelPollingJob = scope.launch(Dispatchers.IO) {
            while (true) {
                val sources = withContext(Dispatchers.Main.immediate) {
                    val currentState = repository.state.value
                    AudioLevelSources(
                        localUserId = currentState.ownUserId.takeIf {
                            currentState.voiceChannelId != null && currentState.microphoneEnabled
                        },
                        microphoneProducer = microphoneProducer.takeIf { currentState.microphoneEnabled },
                        remoteAudioConsumers = consumers.mapNotNull { (key, consumer) ->
                            if (consumer.kind != "audio" || key.substringAfter(':') != "audio") {
                                return@mapNotNull null
                            }
                            key.substringBefore(':').toIntOrNull()?.let { it to consumer }
                        }
                    )
                }
                val activeSpeakerIds = buildSet {
                    sources.localUserId?.let { userId ->
                        val stats = runCatching { sources.microphoneProducer?.stats }.getOrNull()
                        if (isVoiceSpeaking(producerAudioLevel(stats))) add(userId)
                    }
                    sources.remoteAudioConsumers.forEach { (userId, consumer) ->
                        val stats = runCatching { consumer.stats }.getOrNull()
                        if (isVoiceSpeaking(consumerAudioLevel(stats))) add(userId)
                    }
                }
                currentCoroutineContext().ensureActive()
                if (activeSpeakerIds != mutableActiveSpeakerIds.value) {
                    mutableActiveSpeakerIds.value = activeSpeakerIds
                }
                delay(AUDIO_LEVEL_POLL_INTERVAL_MS)
            }
        }
    }

    private fun stopAudioLevelPolling() {
        audioLevelPollingJob?.cancel()
        audioLevelPollingJob = null
        mutableActiveSpeakerIds.value = emptySet()
    }

    private suspend fun reconcileProducers(channelId: Int) {
        val remoteIds = repository.getVoiceProducers()
        val remoteKinds = buildList {
            remoteIds.remoteAudioIds.forEach { add(it to "audio") }
            remoteIds.remoteVideoIds.forEach { add(it to "video") }
            remoteIds.remoteScreenIds.forEach { add(it to "screen") }
            remoteIds.remoteScreenAudioIds.forEach { add(it to "screen_audio") }
        }
        remoteKinds.filter { it.first != repository.state.value.ownUserId }
            .forEach { (remoteId, kind) -> consume(remoteId, kind) }
        if (repository.state.value.voiceChannelId != channelId) return
    }

    private suspend fun consume(remoteId: Int, kind: String) = mutex.withLock {
        val key = consumerKey(remoteId, kind)
        if (consumers.containsKey(key)) return
        val localDevice = device ?: return
        val transport = recvTransport ?: return
        try {
            val capabilities = Json.parseToJsonElement(localDevice.getRtpCapabilities()).jsonObject
            val result = repository.consumeVoice(kind, remoteId, capabilities)
            val mediaKind = if (kind == "audio" || kind == "screen_audio") "audio" else "video"
            val consumer = transport.consume(
                consumerListener,
                result.consumerId,
                result.producerId,
                mediaKind,
                result.consumerRtpParameters.toString(),
                null
            )
            val isAudioEnabled = repository.state.value.speakerEnabled
            if (mediaKind == "audio") consumer.track?.setEnabled(isAudioEnabled)
            consumers[key] = consumer
            val videoTrack = consumer.track as? VideoTrack
            if (videoTrack != null) {
                videoTrack.setEnabled(true)
                mutableVideoTracks.value = mutableVideoTracks.value.filterNot { it.key == key } +
                    RemoteVideoTrack(key, remoteId, kind, videoTrack, result.qualityLayers)
            }
            repository.updateVoiceMediaState(consumedRemoteStreams = consumers.keys.toSet())
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            repository.setError(error.message ?: appContext.getString(R.string.voice_stream_failed), error)
        }
    }

    private fun closeConsumer(remoteId: Int, kind: String) {
        val key = consumerKey(remoteId, kind)
        consumers.remove(key)?.close()
        mutableVideoTracks.value = mutableVideoTracks.value.filterNot { it.key == key }
        repository.updateVoiceMediaState(consumedRemoteStreams = consumers.keys.toSet())
    }

    private val sendListener = object : SendTransport.Listener {
        override fun onConnect(transport: Transport, dtlsParameters: String) {
            connectTransportOnce(producerTransportConnected, dtlsParameters, repository::connectProducerTransport)
        }

        override fun onConnectionStateChange(transport: Transport, connectionState: String) = Unit

        override fun onProduce(transport: Transport, kind: String, rtpParameters: String, appData: String): String {
            return runBlocking(Dispatchers.IO) {
                repository.produceVoice(
                    transport.id,
                    producerKindFromAppData(kind, appData),
                    Json.parseToJsonElement(rtpParameters).jsonObject
                )
            }
        }

        override fun onProduceData(
            transport: Transport,
            sctpStreamParameters: String,
            label: String,
            protocol: String,
            appData: String
        ): String = throw UnsupportedOperationException("Data channels are not used by cove")
    }

    private val receiveListener = object : RecvTransport.Listener {
        override fun onConnect(transport: Transport, dtlsParameters: String) {
            connectTransportOnce(consumerTransportConnected, dtlsParameters, repository::connectConsumerTransport)
        }

        override fun onConnectionStateChange(transport: Transport, connectionState: String) = Unit
    }

    private fun connectTransportOnce(
        connected: AtomicBoolean,
        dtlsParameters: String,
        connect: suspend (JsonObject) -> Unit
    ) {
        if (!connected.compareAndSet(false, true)) return
        try {
            runBlocking(Dispatchers.IO) {
                connect(Json.parseToJsonElement(dtlsParameters).jsonObject)
            }
        } catch (error: Throwable) {
            connected.set(false)
            throw error
        }
    }

    private val producerListener = object : Producer.Listener {
        override fun onTransportClose(producer: Producer) = Unit
    }

    private val consumerListener = object : Consumer.Listener {
        override fun onTransportClose(consumer: Consumer) = Unit
    }

    private fun stopScreenCapture() {
        runCatching { screenCapturer?.stopCapture() }
        screenCapturer?.dispose()
        screenCapturer = null
        screenTrack?.dispose()
        screenTrack = null
        screenSource?.dispose()
        screenSource = null
        surfaceTextureHelper?.dispose()
        surfaceTextureHelper = null
    }

    private fun stopCameraCapture() {
        runCatching { cameraCapturer?.stopCapture() }
        cameraCapturer?.dispose()
        cameraCapturer = null
        cameraTrack?.dispose()
        cameraTrack = null
        cameraSource?.dispose()
        cameraSource = null
        cameraTextureHelper?.dispose()
        cameraTextureHelper = null
        mutableLocalCameraTrack.value = null
    }

    private fun closeMediaObjects() {
        stopAudioLevelPolling()
        producerTransportConnected.set(false)
        consumerTransportConnected.set(false)
        microphoneTrack?.setEnabled(false)
        microphoneProducer?.close()
        microphoneProducer = null
        screenProducer?.close()
        screenProducer = null
        stopScreenCapture()
        cameraProducer?.close()
        cameraProducer = null
        stopCameraCapture()
        consumers.values.forEach { consumer ->
            consumer.close()
        }
        consumers.clear()
        mutableVideoTracks.value = emptyList()
        sendTransport?.close()
        sendTransport?.dispose()
        sendTransport = null
        recvTransport?.close()
        recvTransport?.dispose()
        recvTransport = null
        device?.dispose()
        device = null
        microphoneTrack?.dispose()
        microphoneTrack = null
        microphoneSource?.dispose()
        microphoneSource = null
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
        audioDeviceModule?.release()
        audioDeviceModule = null
        microphoneWasEnabledBeforeDeafen = false
    }

    private fun getOrCreateEglBase(): EglBase = eglBase ?: EglBase.create().also { base ->
        eglBase = base
        mutableEglBaseContext.value = base.eglBaseContext
    }

    private fun startVoiceService() {
        appContext.startForegroundService(voiceServiceIntent(VoiceCallService.ACTION_START_MICROPHONE))
    }

    private fun startCallService() {
        appContext.startForegroundService(voiceServiceIntent(VoiceCallService.ACTION_START_CALL))
    }

    private suspend fun startScreenService() {
        val microphoneGranted = appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val foregroundReady = CompletableDeferred<Unit>()
        val resultReceiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                if (resultCode == Activity.RESULT_OK) {
                    foregroundReady.complete(Unit)
                } else {
                    foregroundReady.completeExceptionally(
                        IllegalStateException(
                            resultData?.getString(VoiceCallService.EXTRA_FOREGROUND_ERROR)
                                ?: appContext.getString(R.string.screen_share_failed)
                        )
                    )
                }
            }
        }
        val intent = voiceServiceIntent(VoiceCallService.ACTION_START_SCREEN)
            .putExtra(VoiceCallService.EXTRA_INCLUDE_MICROPHONE, microphoneGranted && repository.state.value.microphoneEnabled)
            .putExtra(VoiceCallService.EXTRA_INCLUDE_CAMERA, cameraCapturer != null)
            .putExtra(VoiceCallService.EXTRA_FOREGROUND_RESULT_RECEIVER, resultReceiver)
        appContext.startForegroundService(intent)
        val started = withTimeoutOrNull(5_000) { foregroundReady.await() }
        if (started == null) throw IllegalStateException(appContext.getString(R.string.screen_share_failed))
    }

    private suspend fun startCameraService() {
        val microphoneGranted = appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val foregroundReady = CompletableDeferred<Unit>()
        val resultReceiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                if (resultCode == Activity.RESULT_OK) {
                    foregroundReady.complete(Unit)
                } else {
                    foregroundReady.completeExceptionally(
                        IllegalStateException(
                            resultData?.getString(VoiceCallService.EXTRA_FOREGROUND_ERROR)
                                ?: appContext.getString(R.string.camera_start_failed)
                        )
                    )
                }
            }
        }
        val intent = voiceServiceIntent(VoiceCallService.ACTION_START_CAMERA)
            .putExtra(VoiceCallService.EXTRA_INCLUDE_MICROPHONE, microphoneGranted && repository.state.value.microphoneEnabled)
            .putExtra(VoiceCallService.EXTRA_INCLUDE_PROJECTION, screenCapturer != null)
            .putExtra(VoiceCallService.EXTRA_FOREGROUND_RESULT_RECEIVER, resultReceiver)
        appContext.startForegroundService(intent)
        val started = withTimeoutOrNull(5_000) { foregroundReady.await() }
        if (started == null) throw IllegalStateException(appContext.getString(R.string.camera_start_failed))
    }

    private fun setSpeakerphoneEnabled(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (enabled) {
                audioManager.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let(audioManager::setCommunicationDevice)
            } else {
                audioManager.clearCommunicationDevice()
            }
        } else {
            audioManager.isSpeakerphoneOn = enabled
        }
    }

    private suspend fun syncVoiceService() {
        val currentState = repository.state.value
        if (currentState.voiceChannelId == null) {
            stopVoiceService()
        } else if (screenCapturer != null) {
            startScreenService()
        } else if (cameraCapturer != null) {
            startCameraService()
        } else if (currentState.microphoneEnabled) {
            startVoiceService()
        } else {
            startCallService()
        }
    }

    private fun stopVoiceService() {
        appContext.stopService(Intent(appContext, VoiceCallService::class.java))
    }

    private fun voiceServiceIntent(action: String): Intent {
        val snapshot = requireNotNull(VoiceCallNotificationSnapshot.from(repository.state.value))
        return VoiceCallService.createIntent(appContext, action, snapshot)
    }

    private fun consumerKey(remoteId: Int, kind: String) = "$remoteId:$kind"

    companion object {
        private const val AUDIO_LEVEL_POLL_INTERVAL_MS = 200L
        @Volatile private var mediasoupInitialized = false
        @Volatile private var peerConnectionFactoryInitialized = false

        @Synchronized
        private fun initializePeerConnectionFactory(context: Context) {
            if (peerConnectionFactoryInitialized) return
            val options = PeerConnectionFactory.InitializationOptions.builder(context)
                .createInitializationOptions()
            PeerConnectionFactory.initialize(options)
            peerConnectionFactoryInitialized = true
        }
    }
}

internal fun producerKindFromAppData(kind: String, appData: String): String = runCatching {
    Json.parseToJsonElement(appData).jsonObject["kind"]?.jsonPrimitive?.contentOrNull
}.getOrNull()?.takeIf { it.isNotBlank() } ?: kind
