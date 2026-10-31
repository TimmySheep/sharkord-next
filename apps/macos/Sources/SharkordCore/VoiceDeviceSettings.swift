import Foundation

/// One capture or playback endpoint as the media engine sees it. The id is the
/// browser-scoped device id returned by `enumerateDevices`, not a native CoreAudio
/// uid, because the capture happens inside the voice webview rather than in-process.
public struct VoiceMediaDevice: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let deviceId: String
    public let label: String

    public var id: String { deviceId }

    public init(deviceId: String, label: String) {
        self.deviceId = deviceId
        self.label = label
    }
}

/// The device list the worker reports, grouped by media kind.
public struct VoiceEnumeratedDevices: Codable, Equatable, Sendable {
    public let inputs: [VoiceMediaDevice]
    public let outputs: [VoiceMediaDevice]
    public let videos: [VoiceMediaDevice]

    public init(inputs: [VoiceMediaDevice], outputs: [VoiceMediaDevice], videos: [VoiceMediaDevice]) {
        self.inputs = inputs
        self.outputs = outputs
        self.videos = videos
    }

    public static let empty = VoiceEnumeratedDevices(inputs: [], outputs: [], videos: [])

    /// Drops ids whose device is no longer attached so a stale selection falls back to
    /// the platform default instead of failing an exact `getUserMedia` match. An empty
    /// list is left untouched because it only means the labels are not readable yet.
    public func resolved(_ settings: VoiceDeviceSettings) -> VoiceDeviceSettings {
        var resolved = settings

        if !inputs.isEmpty {
            resolved.microphoneId = Self.resolve(settings.microphoneId, in: inputs)
        }
        if !outputs.isEmpty {
            resolved.playbackId = Self.resolve(settings.playbackId, in: outputs)
        }
        if !videos.isEmpty {
            resolved.webcamId = Self.resolve(settings.webcamId, in: videos)
        }

        return resolved
    }

    private static func resolve(_ id: String?, in devices: [VoiceMediaDevice]) -> String? {
        guard let id, !id.isEmpty else {
            return nil
        }
        return devices.contains(where: { $0.deviceId == id }) ? id : nil
    }
}

/// Capture preferences that survive an engine restart. An absent id means "let the
/// platform pick its default", which is why the ids are optional rather than empty
/// strings: an empty device id would be handed to `getUserMedia` as an exact match
/// and fail instead of falling back.
public struct VoiceDeviceSettings: Codable, Equatable, Sendable {
    public var microphoneId: String?
    public var playbackId: String?
    public var webcamId: String?
    public var echoCancellation: Bool
    public var autoGainControl: Bool

    public init(
        microphoneId: String? = nil,
        playbackId: String? = nil,
        webcamId: String? = nil,
        echoCancellation: Bool = true,
        autoGainControl: Bool = true
    ) {
        self.microphoneId = microphoneId
        self.playbackId = playbackId
        self.webcamId = webcamId
        self.echoCancellation = echoCancellation
        self.autoGainControl = autoGainControl
    }

    public static let `default` = VoiceDeviceSettings()

    /// Payload handed to `window.coveVoice.setDeviceSettings`. A nil id is sent as an
    /// empty string, which the worker normalizes back to "no exact constraint" so the
    /// platform default device is used instead of a failed exact match.
    public var bridgePayload: [String: Any] {
        [
            "microphoneId": microphoneId ?? "",
            "playbackId": playbackId ?? "",
            "webcamId": webcamId ?? "",
            "echoCancellation": echoCancellation,
            "autoGainControl": autoGainControl
        ]
    }
}

/// UserDefaults persistence for `VoiceDeviceSettings`, kept in core so the controller
/// and any future caller share one storage key and one decode fallback path.
public enum VoiceDeviceSettingsStore {
    public static let storageKey = "voice.deviceSettings"

    public static func load(from defaults: UserDefaults = .standard) -> VoiceDeviceSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return .default
        }
        return (try? JSONDecoder().decode(VoiceDeviceSettings.self, from: data)) ?? .default
    }

    public static func save(_ settings: VoiceDeviceSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
