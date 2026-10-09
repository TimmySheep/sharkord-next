import AVFoundation
import Combine
import CoreVideo
import Foundation
import Mediasoup
import SharkordCore
import WebRTC

enum VoiceError: LocalizedError {
    case notInCall
    case microphoneBlockedByDeafen
    case screenShareNotAllowed
    case screenShareUnavailable
    case screenBroadcastAppGroupMissing
    case cameraNotAllowed
    case cameraAccessRequired
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .notInCall:
            return L10n.t("voice.error.notInCall")
        case .microphoneBlockedByDeafen:
            return L10n.t("voice.error.micBlockedByDeafen")
        case .screenShareNotAllowed:
            return L10n.t("voice.error.screenShareNotAllowed")
        case .screenShareUnavailable:
            return L10n.t("voice.error.screenShareUnavailable")
        case .screenBroadcastAppGroupMissing:
            return L10n.t("voice.error.screenBroadcastAppGroupMissing")
        case .cameraNotAllowed:
            return L10n.t("voice.error.cameraNotAllowed")
        case .cameraAccessRequired:
            return L10n.t("voice.error.cameraAccessRequired")
        case .cameraUnavailable:
            return L10n.t("voice.error.cameraUnavailable")
        }
    }
}

/// The media half of a voice session. `SharkordSession` owns the mediasoup signalling
/// (join, transports, produce, consume, state updates); this class owns the device, the
/// transports and the tracks, and mirrors the web client's call rules:
///
/// - a muted microphone keeps its producer alive and only disables the track;
/// - while the output is off ("deafened", `soundMuted` on the wire) the microphone
///   **cannot** be turned on at all, which is the protection `canEnableMicrophone`
///   encodes and the UI is expected to surface before the user taps;
/// - deafening also silences every remote audio track locally.
@MainActor
final class VoiceEngine: ObservableObject {
    enum CallState: Equatable {
        case idle
        case joining
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var callState: CallState = .idle
    @Published private(set) var microphoneOn = false
    @Published private(set) var deafened = false
    @Published private(set) var screenSharing = false
    @Published private(set) var screenShareStarting = false
    @Published private(set) var cameraOn = false
    @Published private(set) var cameraStarting = false
    @Published private(set) var localCameraTrack: RTCVideoTrack?
    @Published private(set) var currentChannelId: Int?
    @Published private(set) var lastCallChannelId: Int?
    @Published private(set) var consumedRemoteIds: Set<String> = []
    @Published private(set) var remoteVideoStreams: [RemoteVideoStream] = []
    @Published var lastErrorMessage: String?

    private let session: SharkordSession
    private let factory = RTCPeerConnectionFactory()
    private var device: Device?
    private var sendTransport: SendTransport?
    private var receiveTransport: ReceiveTransport?
    private var microphoneProducer: Producer?
    private var cameraProducer: Producer?
    private var cameraCapturer: RTCCameraVideoCapturer?
    private var cameraSource: RTCVideoSource?
    private var cameraTrack: RTCVideoTrack?
    private var cameraDevice: AVCaptureDevice?
    private var screenProducer: Producer?
    private var screenCapturer: ScreenShareCapturer?
    private var screenSource: RTCVideoSource?
    private var screenBroadcastServer: ScreenBroadcastSocketServer?
    private var screenBroadcastID: UUID?
    private var consumers: [String: Consumer] = [:]

    /// `SendTransportDelegate.onProduce` reports the media kind, not the stream kind the
    /// server expects ("screen" vs "video"), so the intended kind is queued here right
    /// before the producer is created and popped when the delegate fires.
    private var pendingProduceKinds: [ProducibleKind] = []
    private var micWasOnBeforeDeafen = false

    init(session: SharkordSession) {
        self.session = session
    }

    // MARK: - call rules

    /// The protection: an output-muted client must not be able to open its microphone.
    static func canEnableMicrophone(deafened: Bool) -> Bool {
        !deafened
    }

    var canEnableMicrophone: Bool {
        Self.canEnableMicrophone(deafened: deafened)
    }

    // MARK: - call lifecycle

    func join(channelId: Int) async {
        if callState == .joining || callState == .connecting {
            return
        }
        guard currentChannelId != channelId else {
            return
        }

        if currentChannelId != nil {
            await leave()
        }

        currentChannelId = channelId
        lastCallChannelId = channelId
        callState = .joining
        lastErrorMessage = nil

        do {
            // joining muted is the mobile default: the call comes up silent and the user
            // decides when to speak
            let joinResult = try await session.joinVoice(channelId: channelId, micMuted: true, soundMuted: deafened)

            let device = Device(captureAudioSession: true)
            try device.load(with: RTPCodec.string(from: joinResult["routerRtpCapabilities"] ?? .null))
            self.device = device

            callState = .connecting

            let sendParams = try await session.createProducerTransport()
            let send = try device.createSendTransport(
                id: sendParams.id,
                iceParameters: RTPCodec.string(from: sendParams.iceParameters ?? .null),
                iceCandidates: RTPCodec.string(from: sendParams.iceCandidates ?? .null),
                dtlsParameters: RTPCodec.string(from: sendParams.dtlsParameters ?? .null),
                sctpParameters: nil,
                appData: nil
            )
            send.delegate = self
            sendTransport = send

            let receiveParams = try await session.createConsumerTransport()
            let receive = try device.createReceiveTransport(
                id: receiveParams.id,
                iceParameters: RTPCodec.string(from: receiveParams.iceParameters ?? .null),
                iceCandidates: RTPCodec.string(from: receiveParams.iceCandidates ?? .null),
                dtlsParameters: RTPCodec.string(from: receiveParams.dtlsParameters ?? .null)
            )
            receive.delegate = self
            receiveTransport = receive

            configureAudioSession()
            microphoneOn = false
            screenSharing = false
            cameraOn = false
            callState = .connected

            await reconcileProducers()
        } catch {
            let message = error.localizedDescription
            microphoneProducer?.close()
            microphoneProducer = nil
            cameraProducer?.close()
            cameraProducer = nil
            screenProducer?.close()
            screenProducer = nil
            consumers.values.forEach { $0.close() }
            consumers.removeAll()
            consumedRemoteIds.removeAll()
            remoteVideoStreams.removeAll()
            sendTransport?.close()
            sendTransport = nil
            receiveTransport?.close()
            receiveTransport = nil
            device = nil
            pendingProduceKinds.removeAll()
            microphoneOn = false
            cameraOn = false
            localCameraTrack = nil
            try? await session.leaveVoice()
            currentChannelId = nil
            callState = .failed(message)
            lastErrorMessage = message
        }
    }

    func leave() async {
        guard currentChannelId != nil else {
            if screenBroadcastServer != nil || screenShareStarting || screenSharing || screenProducer != nil {
                await stopScreenShare()
            }
            lastCallChannelId = nil
            callState = .idle
            lastErrorMessage = nil
            return
        }

        currentChannelId = nil
        lastCallChannelId = nil

        if screenSharing || screenShareStarting || screenBroadcastServer != nil || screenCapturer != nil || screenProducer != nil {
            await stopScreenShare()
        }
        if cameraOn || cameraProducer != nil || cameraCapturer != nil {
            await stopCamera()
        }

        microphoneProducer?.close()
        microphoneProducer = nil
        screenProducer?.close()
        screenProducer = nil
        cameraProducer?.close()
        cameraProducer = nil

        consumers.values.forEach { $0.close() }
        consumers.removeAll()
        consumedRemoteIds.removeAll()
        remoteVideoStreams.removeAll()

        sendTransport?.close()
        sendTransport = nil
        receiveTransport?.close()
        receiveTransport = nil
        device = nil
        pendingProduceKinds.removeAll()
        microphoneOn = false
        cameraOn = false
        localCameraTrack = nil
        micWasOnBeforeDeafen = false

        try? await session.leaveVoice()
        callState = .idle
    }

    // MARK: - microphone and output

    func setMicrophoneEnabled(_ enabled: Bool) async throws {
        guard currentChannelId != nil else {
            throw VoiceError.notInCall
        }

        if enabled {
            // the protection: a deafened client never opens its microphone, even if the
            // request comes from somewhere other than the button
            guard canEnableMicrophone else {
                throw VoiceError.microphoneBlockedByDeafen
            }

            let producer = try ensureMicrophoneProducer()
            producer.track.isEnabled = true
            microphoneOn = true
            try await session.updateVoiceState(micMuted: false)
        } else {
            microphoneProducer?.track.isEnabled = false
            microphoneOn = false
            try await session.updateVoiceState(micMuted: true)
        }
    }

    func setDeafened(_ on: Bool) async throws {
        guard currentChannelId != nil else {
            throw VoiceError.notInCall
        }

        if on {
            micWasOnBeforeDeafen = microphoneOn
            if microphoneOn {
                try await setMicrophoneEnabled(false)
            }
            deafened = true
            setRemoteAudioEnabled(false)
            try await session.updateVoiceState(micMuted: true, soundMuted: true)
        } else {
            deafened = false
            setRemoteAudioEnabled(true)
            try await session.updateVoiceState(soundMuted: false)
            if micWasOnBeforeDeafen {
                micWasOnBeforeDeafen = false
                try await setMicrophoneEnabled(true)
            }
        }
    }

    // MARK: - camera

    func startCamera() async throws {
        guard let channelId = currentChannelId, let transport = sendTransport else {
            throw VoiceError.notInCall
        }
        guard !cameraOn, !cameraStarting, cameraProducer == nil, cameraCapturer == nil else {
            return
        }
        cameraStarting = true
        defer { cameraStarting = false }
        guard session.hasPermission(.enableWebcam), session.hasChannelPermission(channelId, .webcam) else {
            throw VoiceError.cameraNotAllowed
        }
        try await requestCameraAccess()

        guard let device = preferredCamera(position: .front),
              let format = preferredCameraFormat(for: device) else {
            throw VoiceError.cameraUnavailable
        }

        let source = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: source)
        do {
            try await startCapture(capturer, device: device, format: format)
            let track = factory.videoTrack(with: source, trackId: "video-\(channelId)")
            pendingProduceKinds.append(.video)
            let producer = try transport.createProducer(
                for: track,
                encodings: nil,
                codecOptions: nil,
                codec: nil,
                appData: nil
            )
            try await session.updateVoiceState(webcamEnabled: true)
            cameraSource = source
            cameraCapturer = capturer
            cameraTrack = track
            cameraDevice = device
            cameraProducer = producer
            localCameraTrack = track
            cameraOn = true
        } catch {
            pendingProduceKinds.removeAll { $0 == .video }
            await stopCapture(capturer)
            try? await session.closeProducer(kind: .video)
            try? await session.updateVoiceState(webcamEnabled: false)
            throw error
        }
    }

    func stopCamera() async {
        let producer = cameraProducer
        cameraProducer = nil
        cameraOn = false
        localCameraTrack = nil

        producer?.close()
        if producer != nil {
            try? await session.closeProducer(kind: .video)
        }
        try? await session.updateVoiceState(webcamEnabled: false)

        if let cameraCapturer {
            await stopCapture(cameraCapturer)
        }
        cameraCapturer = nil
        cameraTrack = nil
        cameraSource = nil
        cameraDevice = nil
    }

    func switchCamera() async throws {
        guard let cameraCapturer, let currentDevice = cameraDevice else {
            throw VoiceError.cameraUnavailable
        }
        guard let nextDevice = RTCCameraVideoCapturer.captureDevices().first(where: {
            $0.position != currentDevice.position
        }), let format = preferredCameraFormat(for: nextDevice) else {
            throw VoiceError.cameraUnavailable
        }
        guard let previousFormat = preferredCameraFormat(for: currentDevice) else {
            throw VoiceError.cameraUnavailable
        }
        await stopCapture(cameraCapturer)
        do {
            try await startCapture(cameraCapturer, device: nextDevice, format: format)
            self.cameraDevice = nextDevice
        } catch {
            try? await startCapture(cameraCapturer, device: currentDevice, format: previousFormat)
            throw error
        }
    }

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw VoiceError.cameraAccessRequired
            }
        default:
            throw VoiceError.cameraAccessRequired
        }
    }

    private func preferredCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = RTCCameraVideoCapturer.captureDevices()
        return devices.first(where: { $0.position == position }) ?? devices.first
    }

    private func preferredCameraFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        RTCCameraVideoCapturer.supportedFormats(for: device)
            .filter { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 24 }
            }
            .min { left, right in
                let leftDimensions = CMVideoFormatDescriptionGetDimensions(left.formatDescription)
                let rightDimensions = CMVideoFormatDescriptionGetDimensions(right.formatDescription)
                let leftDistance = abs(Int(leftDimensions.width * leftDimensions.height) - 1280 * 720)
                let rightDistance = abs(Int(rightDimensions.width * rightDimensions.height) - 1280 * 720)
                return leftDistance < rightDistance
            }
    }

    private func startCapture(
        _ capturer: RTCCameraVideoCapturer,
        device: AVCaptureDevice,
        format: AVCaptureDevice.Format
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: 24) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ capturer: RTCCameraVideoCapturer) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            capturer.stopCapture {
                continuation.resume()
            }
        }
    }

    // MARK: - screen share

    func prepareScreenBroadcast() throws {
        guard let channelId = currentChannelId, sendTransport != nil else {
            throw VoiceError.notInCall
        }
        guard screenBroadcastServer == nil, !screenSharing else {
            return
        }

        guard session.hasPermission(.shareScreen), session.hasChannelPermission(channelId, .shareScreen) else {
            throw VoiceError.screenShareNotAllowed
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ScreenBroadcastConfiguration.appGroupIdentifier
        ) else {
            throw VoiceError.screenBroadcastAppGroupMissing
        }

        let source = factory.videoSource()
        screenSource = source
        let capturer = ScreenShareCapturer(delegate: source)
        screenCapturer = capturer
        let operationID = UUID()
        screenBroadcastID = operationID
        let server = ScreenBroadcastSocketServer(
            containerURL: containerURL,
            onConnect: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.activateScreenBroadcast(operationID: operationID)
                }
            },
            onFrame: { [capturer] pixelBuffer, rotation in
                capturer.push(pixelBuffer, rotation: rotation)
            },
            onDisconnect: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.screenBroadcastEnded(operationID: operationID)
                }
            }
        )

        do {
            try server.start()
        } catch {
            screenBroadcastID = nil
            screenCapturer = nil
            screenSource = nil
            throw VoiceError.screenShareUnavailable
        }

        screenBroadcastServer = server
        screenShareStarting = true
    }

    func stopScreenShare() async {
        if screenSharing, let server = screenBroadcastServer, let operationID = screenBroadcastID {
            screenSharing = false
            screenShareStarting = false
            let producer = screenProducer
            screenProducer = nil
            producer?.close()
            if producer != nil {
                pendingProduceKinds.removeAll { $0 == .screen }
                try? await session.closeProducer(kind: .screen)
                try? await session.updateVoiceState(sharingScreen: false)
            }
            server.requestStop()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.screenBroadcastID == operationID else {
                    return
                }
                await self.finishScreenBroadcast(requestExtensionStop: false)
            }
            return
        }

        await finishScreenBroadcast(requestExtensionStop: true)
    }

    func cancelScreenBroadcastPreparation() {
        guard !screenSharing else {
            return
        }

        Task { @MainActor in
            await finishScreenBroadcast(requestExtensionStop: false)
        }
    }

    private func activateScreenBroadcast(operationID: UUID) async {
        guard screenBroadcastID == operationID,
              screenShareStarting,
              let channelId = currentChannelId,
              let transport = sendTransport,
              let source = screenSource
        else {
            return
        }

        guard session.hasPermission(.shareScreen), session.hasChannelPermission(channelId, .shareScreen) else {
            lastErrorMessage = VoiceError.screenShareNotAllowed.localizedDescription
            await finishScreenBroadcast(requestExtensionStop: true)
            return
        }

        let track = factory.videoTrack(with: source, trackId: "screen-\(channelId)")
        pendingProduceKinds.append(.screen)

        do {
            let producer = try transport.createProducer(
                for: track,
                encodings: nil,
                codecOptions: nil,
                codec: nil,
                appData: nil
            )
            screenProducer = producer
            try await session.updateVoiceState(sharingScreen: true)
            guard screenBroadcastID == operationID else {
                await finishScreenBroadcast(requestExtensionStop: true)
                return
            }
            screenShareStarting = false
            screenSharing = true
        } catch {
            pendingProduceKinds.removeAll { $0 == .screen }
            lastErrorMessage = error.localizedDescription
            await finishScreenBroadcast(requestExtensionStop: true)
        }
    }

    private func screenBroadcastEnded(operationID: UUID) async {
        guard screenBroadcastID == operationID else {
            return
        }

        await finishScreenBroadcast(requestExtensionStop: false)
    }

    private func finishScreenBroadcast(requestExtensionStop: Bool) async {
        guard screenBroadcastServer != nil || screenShareStarting || screenSharing || screenProducer != nil else {
            return
        }

        let server = screenBroadcastServer
        screenBroadcastServer = nil
        screenBroadcastID = nil
        screenShareStarting = false
        screenSharing = false
        screenCapturer = nil
        screenSource = nil
        let producer = screenProducer
        screenProducer = nil

        if requestExtensionStop {
            server?.requestStop()
        }
        server?.stop()

        if let producer {
            producer.close()
            pendingProduceKinds.removeAll { $0 == .screen }
            try? await session.closeProducer(kind: .screen)
            try? await session.updateVoiceState(sharingScreen: false)
        }
    }

    // MARK: - consumers

    /// Brings the local consumer set in line with what the server says is being produced
    /// in the current channel. Safe to call repeatedly.
    func reconcileProducers() async {
        guard let channelId = currentChannelId, let device else {
            return
        }

        do {
            let producers = try await session.getProducers()
            var wanted: [(remoteId: Int, kind: StreamKind)] = []

            for remoteId in producers.remoteAudioIds where remoteId != session.ownUserId {
                wanted.append((remoteId, .audio))
            }
            for remoteId in producers.remoteVideoIds where remoteId != session.ownUserId {
                wanted.append((remoteId, .video))
            }
            for remoteId in producers.remoteScreenIds where remoteId != session.ownUserId {
                wanted.append((remoteId, .screen))
            }
            for remoteId in producers.remoteScreenAudioIds where remoteId != session.ownUserId {
                wanted.append((remoteId, .screenAudio))
            }

            let channelProducers = session.producersByChannel[channelId] ?? []
            for event in channelProducers where event.remoteId != session.ownUserId {
                if !wanted.contains(where: { $0.remoteId == event.remoteId && $0.kind == event.kind }) {
                    wanted.append((event.remoteId, event.kind))
                }
            }

            for entry in wanted {
                try await consume(remoteId: entry.remoteId, kind: entry.kind, device: device)
            }

            // a producer that disappeared leaves its consumer behind until it is closed
            let wantedKeys = Set(wanted.map { RTPCodec.consumerKey(remoteId: $0.remoteId, kind: $0.kind) })
            for (key, consumer) in consumers where !wantedKeys.contains(key) {
                consumer.close()
                consumers.removeValue(forKey: key)
                consumedRemoteIds.remove(key)
                remoteVideoStreams.removeAll { $0.id == key }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func consume(remoteId: Int, kind: StreamKind, device: Device) async throws {
        let key = RTPCodec.consumerKey(remoteId: remoteId, kind: kind)

        guard consumers[key] == nil, let transport = receiveTransport else {
            return
        }

        let result = try await session.consume(
            kind: kind,
            remoteId: remoteId,
            rtpCapabilities: RTPCodec.value(from: try device.rtpCapabilities())
        )

        let consumer = try transport.consume(
            consumerId: result.consumerId,
            producerId: result.producerId,
            kind: kind == .audio || kind == .screenAudio ? .audio : .video,
            rtpParameters: RTPCodec.string(from: result.consumerRtpParameters ?? .null),
            appData: nil
        )

        if deafened, consumer.kind == .audio {
            consumer.track.isEnabled = false
        }

        consumers[key] = consumer
        consumedRemoteIds.insert(key)

        if consumer.kind == .video, let videoTrack = consumer.track as? RTCVideoTrack {
            let stream = RemoteVideoStream(
                id: key,
                remoteId: remoteId,
                kind: kind,
                track: videoTrack,
                qualityLayers: result.qualityLayers ?? []
            )
            remoteVideoStreams.removeAll { $0.id == key }
            remoteVideoStreams.append(stream)
        }
    }

    private func setRemoteAudioEnabled(_ enabled: Bool) {
        for consumer in consumers.values where consumer.kind == .audio {
            consumer.track.isEnabled = enabled
        }
    }

    func setQuality(for stream: RemoteVideoStream, spatialLayer: Int?) async {
        do {
            try await session.setConsumerQuality(
                remoteId: stream.remoteId,
                kind: stream.kind,
                spatialLayer: spatialLayer
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func ensureMicrophoneProducer() throws -> Producer {
        if let microphoneProducer {
            return microphoneProducer
        }

        guard let transport = sendTransport else {
            throw VoiceError.notInCall
        }

        let track = factory.audioTrack(withTrackId: "microphone")
        pendingProduceKinds.append(.audio)

        do {
            let producer = try transport.createProducer(
                for: track,
                encodings: nil,
                codecOptions: nil,
                codec: nil,
                appData: nil
            )
            microphoneProducer = producer
            return producer
        } catch {
            pendingProduceKinds.removeAll { $0 == .audio }
            throw error
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

}

// MARK: - SendTransportDelegate

extension VoiceEngine: SendTransportDelegate {
    nonisolated func onConnect(transport: Transport, dtlsParameters: String) {
        let parameters = RTPCodec.value(from: dtlsParameters)

        Task { @MainActor in
            do {
                if let sendTransport, sendTransport.id == transport.id {
                    try await session.connectProducerTransport(dtlsParameters: parameters)
                } else {
                    try await session.connectConsumerTransport(dtlsParameters: parameters)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func onProduce(
        transport: Transport,
        kind: MediaKind,
        rtpParameters: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        let parameters = RTPCodec.value(from: rtpParameters)

        Task { @MainActor in
            let streamKind = pendingProduceKinds.isEmpty ? (kind == .audio ? .audio : .video) : pendingProduceKinds.removeFirst()

            do {
                let producerId = try await session.produce(
                    transportId: transport.id,
                    kind: streamKind,
                    rtpParameters: parameters
                )
                callback(producerId)
            } catch {
                lastErrorMessage = error.localizedDescription
                callback(nil)
            }
        }
    }

    nonisolated func onProduceData(
        transport: Transport,
        sctpParameters: String,
        label: String,
        protocol dataProtocol: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        // data channels are not part of this version
        callback(nil)
    }

    nonisolated func onConnectionStateChange(transport: Transport, connectionState: TransportConnectionState) {
        Task { @MainActor in
            if case .failed = connectionState {
                lastErrorMessage = L10n.t("voice.error.transportFailed")
            }
        }
    }
}

// MARK: - ReceiveTransportDelegate

extension VoiceEngine: ReceiveTransportDelegate {
}

// MARK: - ReplayKit capture

/// Pushes ReplayKit sample buffers into a WebRTC video source so screen capture can be
/// produced like any other camera track.
final class ScreenShareCapturer: RTCVideoCapturer {
    var source: RTCVideoSource? {
        delegate as? RTCVideoSource
    }

    func push(_ pixelBuffer: CVPixelBuffer, rotation: RTCVideoRotation) {
        let frame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer),
            rotation: rotation,
            timeStampNs: Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
        delegate?.capturer(self, didCapture: frame)
    }
}
