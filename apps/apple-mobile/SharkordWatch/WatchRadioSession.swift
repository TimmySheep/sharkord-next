import AVFAudio
import Foundation

/// The radio session lifecycle the whole watch app is built around. The user picks a
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

/// The media path, kept behind a protocol so phase 2 can plug in the real transport
/// (WebSocket relay to the Sharkord server, Opus frames) without touching the state
/// machine or the UI.
protocol RadioTransport: AnyObject {
    /// Called when the session receives an audio frame from the room.
    var onReceiveFrame: ((Data) -> Void)? { get set }

    func connect(channelId: String) async throws
    func sendFrame(_ data: Data)
    func disconnect()
}

/// Offline stand-in for the transport: accepts frames and counts them so the skeleton can
/// demonstrate the full PTT flow without a server.
final class MockRadioTransport: RadioTransport {
    var onReceiveFrame: ((Data) -> Void)?

    private(set) var sentFrames = 0

    func connect(channelId: String) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    func sendFrame(_ data: Data) {
        sentFrames += 1
    }

    func disconnect() {}
}

/// AVAudioSession plus microphone capture with level metering. This is the real audio
/// plumbing phase 2 reuses: activate on join, capture only while the user holds to talk,
/// deactivate on leave. The captured buffers are handed to the transport as raw PCM;
/// encoding belongs to the transport.
final class RadioAudioEngine {
    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private var isCapturing = false

    /// Activates the play and record session that also keeps the app alive on the wrist
    /// while joined.
    func activate() throws {
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        try session.setActive(true)
    }

    /// Starts microphone capture. `onLevel` reports RMS for the UI meter, `onBuffer`
    /// hands over each PCM buffer for sending.
    func startCapture(onLevel: @escaping (Float) -> Void, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isCapturing else {
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let level = Self.rmsLevel(of: buffer)
            onLevel(level)
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    /// Ends the session; called on explicit leave only.
    func deactivate() throws {
        stopCapture()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else {
            return 0
        }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return 0
        }

        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        return sqrt(sum / Float(frames))
    }
}

/// The watch's radio state machine. Owns the transport and the audio engine; the UI only
/// reads `state` and calls the four verbs below.
@MainActor
final class WatchRadioSession: ObservableObject {
    @Published private(set) var state: RadioState = .idle
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var currentChannelId: String?
    /// output volume, driven by the digital crown
    @Published var volume: Double = 0.8

    private let transport: RadioTransport
    private let audio = RadioAudioEngine()

    init(transport: RadioTransport = MockRadioTransport()) {
        self.transport = transport
    }

    func join(channelId: String) async {
        guard !state.isActive else {
            return
        }

        state = .joining
        currentChannelId = channelId

        do {
            try audio.activate()
            try await transport.connect(channelId: channelId)
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            currentChannelId = nil
            try? audio.deactivate()
        }
    }

    /// Push to talk pressed: start sending. Rejected while joining or leaving so the
    /// microphone can only open inside an established session.
    func beginTransmit() {
        guard state == .listening else {
            return
        }

        do {
            try audio.startCapture(
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        self?.microphoneLevel = level
                    }
                },
                onBuffer: { [weak self] buffer in
                    self?.send(buffer)
                }
            )
            state = .transmitting
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Push to talk released: stop sending, keep listening.
    func endTransmit() {
        guard state == .transmitting else {
            return
        }

        audio.stopCapture()
        microphoneLevel = 0
        state = .listening
    }

    /// The explicit exit. Closes capture, the transport and the audio session.
    func leave() async {
        guard state.isActive else {
            return
        }

        state = .leaving
        endTransmit()
        transport.disconnect()

        do {
            try audio.deactivate()
        } catch {
            // the session is over either way; the next join reactivates it
        }

        currentChannelId = nil
        microphoneLevel = 0
        state = .idle
    }

    private func send(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else {
            return
        }

        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        transport.sendFrame(Data(buffer: samples))
    }
}
