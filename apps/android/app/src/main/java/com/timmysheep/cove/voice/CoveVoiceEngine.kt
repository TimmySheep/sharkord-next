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
import com.timmysheep.cove.R
import com.timmysheep.cove.data.CoveRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.mediasoup.droid.Consumer
import org.mediasoup.droid.Device
import org.mediasoup.droid.MediasoupClient
import org.mediasoup.droid.PeerConnection
import org.mediasoup.droid.Producer
import org.mediasoup.droid.RecvTransport
import org.mediasoup.droid.SendTransport
import org.mediasoup.droid.Transport
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.EglBase
import org.webrtc.MediaConstraints
import org.webrtc.PeerConnectionFactory
import org.webrtc.ScreenCapturerAndroid
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import org.webrtc.audio.AudioDeviceModule
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.atomic.AtomicReference

data class RemoteVideoTrack(
    val key: String,
    val remoteId: Int,
    val kind: String,
    val track: VideoTrack
)

class CoveVoiceEngine(
    context: Context,
    private val repository: CoveRepository
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val mutableVideoTracks = MutableStateFlow<List<RemoteVideoTrack>>(emptyList())
    private val consumers = mutableMapOf<String, Consumer>()
    private val consumerEvents = mutableListOf<Job>()
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
    private var surfaceTextureHelper: SurfaceTextureHelper? = null
    private var eglBase: EglBase? = null
    private var microphoneWasEnabledBeforeDeafen = false
    private val pendingProduceKind = AtomicReference<String?>(null)

    val remoteVideoTracks: StateFlow<List<RemoteVideoTrack>> = mutableVideoTracks.asStateFlow()

    suspend fun join(channelId: Int) {
        if (repository.state.value.voiceChannelId == channelId && device != null) return
        if (repository.state.value.voiceChannelId != null) leave()

        try {
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
                null
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
                null
            )

            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            setSpeakerphoneEnabled(true)
            repository.updateVoiceMediaState(microphoneEnabled = false, speakerEnabled = true)
            startProducerObservers(channelId)
            reconcileProducers(channelId)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            closeMediaObjects()
            runCatching { repository.leaveVoice() }
            repository.setError(error.message ?: appContext.getString(R.string.voice_join_failed))
        }
    }

    suspend fun leave() {
        stopProducerObservers()
        if (screenProducer != null) runCatching { repository.closeVoiceProducer("screen") }
        closeMediaObjects()
        audioManager.mode = AudioManager.MODE_NORMAL
        stopVoiceService()
        runCatching { repository.leaveVoice() }
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
                .onFailure { repository.setError(it.message ?: appContext.getString(R.string.microphone_mute_failed)) }
            if (screenCapturer == null) stopVoiceService()
            return
        }

        if (appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            repository.setError(appContext.getString(R.string.microphone_permission_required))
            return
        }

        try {
            startVoiceService()
            val transport = requireNotNull(sendTransport)
            val track = microphoneTrack ?: createMicrophoneTrack().also { microphoneTrack = it }
            track.setEnabled(false)
            if (microphoneProducer == null) {
                pendingProduceKind.set("audio")
                microphoneProducer = transport.produce(producerListener, track, null, null, null)
                pendingProduceKind.set(null)
            }
            track.setEnabled(true)
            repository.updateVoiceState(micMuted = false)
            repository.updateVoiceMediaState(microphoneEnabled = true)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            pendingProduceKind.set(null)
            microphoneTrack?.setEnabled(false)
            repository.setError(error.message ?: appContext.getString(R.string.microphone_enable_failed))
        }
    }

    suspend fun setSpeakerEnabled(enabled: Boolean) {
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
                stopVoiceServiceIfMicOff()
                setSpeakerphoneEnabled(false)
            } else {
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
            repository.setError(error.message ?: appContext.getString(R.string.speaker_update_failed))
        }
    }

    suspend fun startScreenShare(resultCode: Int, resultData: Intent?) {
        val channelId = repository.state.value.voiceChannelId ?: return
        if (resultCode != Activity.RESULT_OK || resultData == null) return
        if (!repository.canUseChannelPermission(channelId, "SHARE_SCREEN")) {
            repository.setError(appContext.getString(R.string.screen_share_permission_required))
            return
        }

        try {
            startScreenService()
            val factory = requireNotNull(peerConnectionFactory)
            val transport = requireNotNull(sendTransport)
            val base = eglBase ?: EglBase.create().also { eglBase = it }
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
            screenTrack = track
            pendingProduceKind.set("screen")
            screenProducer = transport.produce(producerListener, track, null, null, null)
            pendingProduceKind.set(null)
            repository.updateVoiceState(sharingScreen = true)
            repository.updateVoiceMediaState(sharingScreen = true)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            pendingProduceKind.set(null)
            stopScreenCapture()
            stopVoiceServiceIfMicOff()
            repository.setError(error.message ?: appContext.getString(R.string.screen_share_failed))
        }
    }

    suspend fun stopScreenShare() {
        if (screenProducer == null && screenCapturer == null) return
        screenProducer?.close()
        screenProducer = null
        stopScreenCapture()
        runCatching { repository.closeVoiceProducer("screen") }
        runCatching { repository.updateVoiceState(sharingScreen = false) }
        repository.updateVoiceMediaState(sharingScreen = false)
        stopVoiceServiceIfMicOff()
    }

    fun release() {
        stopProducerObservers()
        closeMediaObjects()
        stopVoiceService()
        scope.cancel()
    }

    private fun initializeMediasoup(routerCapabilities: JsonObject) {
        if (!mediasoupInitialized) {
            MediasoupClient.initialize(appContext)
            mediasoupInitialized = true
        }
        audioDeviceModule = JavaAudioDeviceModule.builder(appContext).createAudioDeviceModule()
        peerConnectionFactory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(requireNotNull(audioDeviceModule))
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
                mutableVideoTracks.value = mutableVideoTracks.value.filterNot { it.key == key } +
                    RemoteVideoTrack(key, remoteId, kind, videoTrack)
            }
            repository.updateVoiceMediaState(consumedRemoteStreams = consumers.keys.toSet())
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            repository.setError(error.message ?: appContext.getString(R.string.voice_stream_failed))
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
            runBlocking(Dispatchers.IO) {
                repository.connectProducerTransport(Json.parseToJsonElement(dtlsParameters).jsonObject)
            }
        }

        override fun onConnectionStateChange(transport: Transport, connectionState: String) = Unit

        override fun onProduce(transport: Transport, kind: String, rtpParameters: String, appData: String): String {
            val producerKind = pendingProduceKind.getAndSet(null) ?: kind
            return runBlocking(Dispatchers.IO) {
                repository.produceVoice(
                    transport.id,
                    producerKind,
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
            runBlocking(Dispatchers.IO) {
                repository.connectConsumerTransport(Json.parseToJsonElement(dtlsParameters).jsonObject)
            }
        }

        override fun onConnectionStateChange(transport: Transport, connectionState: String) = Unit
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

    private fun closeMediaObjects() {
        microphoneTrack?.setEnabled(false)
        microphoneProducer?.close()
        microphoneProducer = null
        screenProducer?.close()
        screenProducer = null
        stopScreenCapture()
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
        eglBase?.release()
        eglBase = null
        microphoneWasEnabledBeforeDeafen = false
    }

    private fun startVoiceService() {
        val intent = Intent(appContext, VoiceCallService::class.java)
            .setAction(VoiceCallService.ACTION_START_MICROPHONE)
        appContext.startForegroundService(intent)
    }

    private fun startScreenService() {
        val microphoneGranted = appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val intent = Intent(appContext, VoiceCallService::class.java)
            .setAction(VoiceCallService.ACTION_START_SCREEN)
            .putExtra(VoiceCallService.EXTRA_INCLUDE_MICROPHONE, microphoneGranted && repository.state.value.microphoneEnabled)
        appContext.startForegroundService(intent)
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

    private fun stopVoiceServiceIfMicOff() {
        if (!repository.state.value.microphoneEnabled && screenCapturer == null) stopVoiceService()
    }

    private fun stopVoiceService() {
        appContext.stopService(Intent(appContext, VoiceCallService::class.java))
    }

    private fun consumerKey(remoteId: Int, kind: String) = "$remoteId:$kind"

    companion object {
        @Volatile private var mediasoupInitialized = false
    }
}
