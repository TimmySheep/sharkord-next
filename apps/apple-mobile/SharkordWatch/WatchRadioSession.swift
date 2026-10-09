import AVFAudio
import Combine
import Foundation
import SharkordCore

/// the radio session lifecycle the whole watch app is built around. The user picks a
/// channel (join), stays in it listening continuously, holds to talk, and leaves
/// explicitly. Nothing here runs in the background on purpose: the audio session keeps
/// the app alive while joined, and leaving closes every resource.
enum RadioState: Equatable {
    case idle
    case joining
    case listening
    case transmitting
    case leaving
    case failed(String)

    var isActive: Bool {
        self == .joining || self == .listening || self == .transmitting || self == .leaving
    }
}

/// the media path stays behind a protocol so lifecycle and UI code do not depend on its transport.
@MainActor
protocol RadioTransport: AnyObject {
    /// called when the session receives an audio frame from the room.
    var onReceiveFrame: ((Int, Data) -> Void)? { get set }

    func connect(channelId: Int) async throws
    func setMicrophoneMuted(_ muted: Bool) async throws
    func sendFrame(_ data: Data) async
    func disconnect(channelId: Int?) async
}

/// AVAudioSession plus microphone capture with level metering. The engine activates on join,
/// captures only while the user holds to talk, and hands raw PCM frames to the server transport.
final class RadioAudioEngine {
    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var players: [AVAudioPlayerNode] = []
    private var playerByUser: [Int: AVAudioPlayerNode] = [:]
    private var converter: AVAudioConverter?
    private var pendingSamples: [Int16] = []
    private let captureLock = NSLock()
    private var isCapturing = false

    /// activates the play and record session for an active radio session.
    func activate() throws {
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        try session.setActive(true)

        if players.isEmpty {
            for _ in 0..<12 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
                players.append(player)
            }
        }

        engine.prepare()
        if !engine.isRunning {
            try engine.start()
        }
    }

    /// starts microphone capture. `onLevel` reports RMS for the UI meter, while `onFrame`
    /// hands over each PCM frame for sending.
    func startCapture(onLevel: @escaping (Float) -> Void, onFrame: @escaping (Data) -> Void) throws {
        guard !isCapturing else {
            return
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw TRPCClientError(code: "AUDIO_FORMAT", message: L10n.t("watch.audioUnavailable"))
        }
        captureLock.lock()
        self.converter = converter
        pendingSamples.removeAll(keepingCapacity: true)
        captureLock.unlock()

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            let level = Self.rmsLevel(of: buffer)
            onLevel(level)
            self?.appendConvertedFrames(buffer, onFrame: onFrame)
        }

        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        captureLock.lock()
        converter = nil
        pendingSamples.removeAll(keepingCapacity: true)
        captureLock.unlock()
        isCapturing = false
    }

    func play(_ data: Data, from userId: Int) {
        guard data.count >= 640, data.count <= 3_840, data.count.isMultiple(of: 2) else {
            return
        }

        let player: AVAudioPlayerNode
        if let existing = playerByUser[userId] {
            player = existing
        } else {
            guard let available = players.first(where: { !playerByUser.values.contains($0) }) else {
                return
            }
            playerByUser[userId] = available
            player = available
            player.play()
        }

        let sampleCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: sampleCount),
              let channel = buffer.int16ChannelData?[0] else {
            return
        }

        data.withUnsafeBytes { bytes in
            guard let samples = bytes.bindMemory(to: Int16.self).baseAddress else {
                return
            }
            channel.update(from: samples, count: Int(sampleCount))
        }
        buffer.frameLength = sampleCount
        player.scheduleBuffer(buffer)
    }

    func setVolume(_ volume: Double) {
        for player in players {
            player.volume = Float(volume)
        }
    }

    func removeUser(_ userId: Int) {
        guard let player = playerByUser.removeValue(forKey: userId) else {
            return
        }

        player.stop()
    }

    /// ends the session; called on explicit leave only.
    func deactivate() throws {
        stopCapture()
        players.forEach { $0.stop() }
        playerByUser.removeAll()
        engine.stop()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func appendConvertedFrames(_ input: AVAudioPCMBuffer, onFrame: @escaping (Data) -> Void) {
        captureLock.lock()
        var frames: [Data] = []
        defer {
            captureLock.unlock()
            frames.forEach(onFrame)
        }

        guard let converter else {
            return
        }

        let capacity = AVAudioFrameCount((Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var providedInput = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            guard !providedInput else {
                status.pointee = .noDataNow
                return nil
            }
            providedInput = true
            status.pointee = .haveData
            return input
        }

        guard conversionError == nil,
              let samples = output.int16ChannelData?[0],
              output.frameLength > 0 else {
            return
        }

        pendingSamples.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
        while pendingSamples.count >= 640 {
            let frame = pendingSamples.withUnsafeBufferPointer { samples in
                Data(buffer: UnsafeBufferPointer(start: samples.baseAddress, count: 640))
            }
            pendingSamples.removeFirst(640)
            frames.append(frame)
        }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return 0
        }

        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<frames {
                let sample = channel[index]
                sum += sample * sample
            }
        } else if let channel = buffer.int16ChannelData?[0] {
            for index in 0..<frames {
                let sample = Float(channel[index]) / Float(Int16.max)
                sum += sample * sample
            }
        } else {
            return 0
        }
        return sqrt(sum / Float(frames))
    }
}

struct WatchRadioCredentials: Sendable {
    let host: String
    let identity: String
    let password: String
    let serverPassword: String?
}

private struct RadioFrameEvent: Decodable {
    let channelId: Int
    let userId: Int
    let seq: Int
    let payload: String
}

/// a second authenticated tRPC socket owns the Watch voice presence and audio relay.
@MainActor
final class WatchRadioTRPCTransport: RadioTransport {
    var onReceiveFrame: ((Int, Data) -> Void)?
    var onRemoveUser: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private let credentials: WatchRadioCredentials
    private var client: TRPCWebSocketClient?
    private var receiveTasks: [Task<Void, Never>] = []
    private var channelId: Int?
    private var sequence = 0
    private var pendingSend: Task<Void, Never>?
    private var pendingSendCount = 0

    init(credentials: WatchRadioCredentials) {
        self.credentials = credentials
    }

    func connect(channelId: Int) async throws {
        guard let baseURL = Self.normalizedURL(credentials.host) else {
            throw TRPCClientError(code: "BAD_REQUEST", message: L10n.t("watch.invalidServerAddress"))
        }

        let http = SharkordHTTPClient(baseURL: baseURL)
        let login = try await http.login(identity: credentials.identity, password: credentials.password)
        let client = TRPCWebSocketClient(configuration: .init(url: http.webSocketURL, token: login.token))
        try await client.connect()

        do {
            let handshake = try await client.query("others.handshake").decode(SharkordHandshake.self)
            var joinInput: [String: JSONValue] = ["handshakeHash": .string(handshake.handshakeHash)]
            if handshake.hasPassword, let serverPassword = credentials.serverPassword, !serverPassword.isEmpty {
                joinInput["password"] = .string(serverPassword)
            }
            _ = try await client.query("others.joinServer", input: .object(joinInput))
            _ = try await client.mutation(
                "voice.join",
                input: .object([
                    "channelId": .int(channelId),
                    "state": .object([
                        "micMuted": .bool(true),
                        "soundMuted": .bool(false)
                    ])
                ])
            )

            self.client = client
            self.channelId = channelId
            let frameStream = await client.subscribe("voice.onRadioFrame")
            let producerClosedStream = await client.subscribe("voice.onProducerClosed")
            let userLeftStream = await client.subscribe("voice.onLeave")
            receiveTasks = [Task { [weak self] in
                do {
                    for try await value in frameStream {
                        guard !Task.isCancelled,
                              let event = try? value.decode(RadioFrameEvent.self),
                              event.channelId == channelId,
                              let data = Data(base64Encoded: event.payload) else {
                            continue
                        }

                        self?.onReceiveFrame?(event.userId, data)
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.onError?(error.localizedDescription)
                    }
                }
            }, Task { [weak self] in
                do {
                    for try await value in producerClosedStream {
                        guard !Task.isCancelled,
                              let event = try? value.decode(VoiceProducerEvent.self),
                              event.channelId == channelId,
                              event.kind == .audio else {
                            continue
                        }
                        self?.onRemoveUser?(event.remoteId)
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.onError?(error.localizedDescription)
                    }
                }
            }, Task { [weak self] in
                do {
                    for try await value in userLeftStream {
                        guard !Task.isCancelled,
                              let event = try? value.decode(VoiceLeaveEvent.self),
                              event.channelId == channelId else {
                            continue
                        }
                        self?.onRemoveUser?(event.userId)
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.onError?(error.localizedDescription)
                    }
                }
            }]
            _ = try await client.mutation(
                "voice.radioStart",
                input: .object(["channelId": .int(channelId)])
            )
        } catch {
            await client.close()
            throw error
        }
    }

    func setMicrophoneMuted(_ muted: Bool) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: L10n.t("watch.disconnected"))
        }

        await pendingSend?.value
        _ = try await client.mutation(
            "voice.updateState",
            input: .object(["micMuted": .bool(muted)])
        )
    }

    func sendFrame(_ data: Data) async {
        // cap queued frames so a slow socket drops stale audio instead of building latency.
        guard let client, let channelId, pendingSendCount < 3 else {
            return
        }

        pendingSendCount += 1
        sequence += 1
        let input: JSONValue = .object([
            "channelId": .int(channelId),
            "seq": .int(sequence),
            "payload": .string(data.base64EncodedString())
        ])

        let previousSend = pendingSend
        pendingSend = Task { [weak self] in
            await previousSend?.value
            do {
                _ = try await client.mutation("voice.radioFrame", input: input)
            } catch {
                self?.onError?(error.localizedDescription)
            }
            if let self {
                self.pendingSendCount -= 1
            }
        }
    }

    func disconnect(channelId: Int?) async {
        receiveTasks.forEach { $0.cancel() }
        receiveTasks.removeAll()
        await pendingSend?.value

        if let client {
            if let joinedChannelId = channelId ?? self.channelId {
                try? await setMicrophoneMuted(true)
                _ = try? await client.mutation("voice.radioStop", input: .object(["channelId": .int(joinedChannelId)]))
                _ = try? await client.mutation("voice.leave")
            }
            await client.close()
        }

        pendingSend = nil
        pendingSendCount = 0
        client = nil
        self.channelId = nil
        sequence = 0
    }

    private static func normalizedURL(_ host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// the watch's radio state machine. Owns the transport and the audio engine; the UI only
/// reads `state` and calls the four verbs below.
@MainActor
final class WatchRadioSession: ObservableObject {
    @Published private(set) var state: RadioState = .idle
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var currentChannelId: Int?
    @Published private(set) var speakingUserIds: Set<Int> = []
    /// output volume, driven by the digital crown
    @Published var volume: Double = 0.8 {
        didSet {
            audio.setVolume(volume)
        }
    }

    private let audio = RadioAudioEngine()
    private var transport: WatchRadioTRPCTransport?
    private var pushToTalkRequest = 0
    private var lastIncomingAudioAt: [Int: Date] = [:]
    private var speakingMonitorTask: Task<Void, Never>?

    init() {}

    func configure(credentials: WatchRadioCredentials) {
        transport = WatchRadioTRPCTransport(credentials: credentials)
        transport?.onReceiveFrame = { [weak self] userId, data in
            self?.noteIncomingAudio(from: userId)
            self?.audio.play(data, from: userId)
        }
        transport?.onRemoveUser = { [weak self] userId in
            self?.audio.removeUser(userId)
            self?.lastIncomingAudioAt.removeValue(forKey: userId)
            self?.speakingUserIds.remove(userId)
        }
        transport?.onError = { [weak self] message in
            guard self?.state == .listening || self?.state == .transmitting else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.fail(message)
            }
        }
    }

    func join(channelId: Int) async {
        guard !state.isActive else {
            return
        }

        DiagnosticsLogger.shared.info("watch.radio", "join requested")

        guard let transport else {
            state = .failed(L10n.t("watch.connectFirst"))
            return
        }

        state = .joining
        currentChannelId = channelId

        do {
            try audio.activate()
            audio.setVolume(volume)
            try await transport.connect(channelId: channelId)
            guard currentChannelId == channelId, state == .joining else {
                await transport.disconnect(channelId: channelId)
                try? audio.deactivate()
                return
            }
            state = .listening
            DiagnosticsLogger.shared.info("watch.radio", "joined and listening")
        } catch {
            DiagnosticsLogger.shared.error("watch.radio", "join failed", error: error)
            state = .failed(error.localizedDescription)
            await transport.disconnect(channelId: channelId)
            currentChannelId = nil
            try? audio.deactivate()
        }
    }

    /// push to talk pressed: start sending. Rejected while joining or leaving so the
    /// microphone can only open inside an established session.
    func beginTransmit() async {
        guard state == .listening else {
            return
        }

        pushToTalkRequest += 1
        let request = pushToTalkRequest
        state = .transmitting

        do {
            guard let transport else {
                throw TRPCClientError(code: "DISCONNECTED", message: L10n.t("watch.disconnected"))
            }
            try await transport.setMicrophoneMuted(false)
            guard request == pushToTalkRequest, state == .transmitting else {
                try? await transport.setMicrophoneMuted(true)
                return
            }
            try audio.startCapture(
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        self?.microphoneLevel = level
                    }
                },
                onFrame: { [weak self] frame in
                    Task { @MainActor [weak self] in
                        guard let self, self.state == .transmitting else {
                            return
                        }
                        await self.transport?.sendFrame(frame)
                    }
                }
            )
        } catch {
            await fail(error.localizedDescription)
        }
    }

    /// push to talk released: stop sending, keep listening.
    func endTransmit() async {
        guard state == .transmitting else {
            return
        }

        pushToTalkRequest += 1
        audio.stopCapture()
        microphoneLevel = 0
        state = .listening
        do {
            try await transport?.setMicrophoneMuted(true)
        } catch {
            await fail(error.localizedDescription)
        }
    }

    /// the explicit exit. Closes capture, the transport and the audio session.
    func leave() async {
        guard state.isActive || currentChannelId != nil else {
            return
        }

        state = .leaving
        DiagnosticsLogger.shared.info("watch.radio", "leave requested")
        pushToTalkRequest += 1
        audio.stopCapture()
        microphoneLevel = 0
        await transport?.disconnect(channelId: currentChannelId)

        do {
            try audio.deactivate()
        } catch {
            // the session is over either way; the next join reactivates it
            DiagnosticsLogger.shared.warning("watch.audio", error.localizedDescription)
        }

        currentChannelId = nil
        state = .idle
        speakingMonitorTask?.cancel()
        speakingMonitorTask = nil
        lastIncomingAudioAt.removeAll()
        speakingUserIds.removeAll()
    }

    private func noteIncomingAudio(from userId: Int) {
        lastIncomingAudioAt[userId] = Date()
        guard speakingMonitorTask == nil else {
            return
        }

        speakingMonitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }

                let cutoff = Date().addingTimeInterval(-0.55)
                let activeUsers = Set(self.lastIncomingAudioAt.compactMap { userId, timestamp in
                    timestamp >= cutoff ? userId : nil
                })
                self.speakingUserIds = activeUsers
                guard !activeUsers.isEmpty else {
                    self.speakingMonitorTask = nil
                    return
                }
            }
        }
    }

    private func fail(_ message: String) async {
        guard state == .listening || state == .transmitting else {
            return
        }

        state = .failed(message)
        DiagnosticsLogger.shared.error("watch.radio", message)
        pushToTalkRequest += 1
        audio.stopCapture()
        microphoneLevel = 0
        await transport?.disconnect(channelId: currentChannelId)
        try? audio.deactivate()
        currentChannelId = nil
    }
}
