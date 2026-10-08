import Foundation

enum VoiceAudioStream: String, CaseIterable, Sendable {
    case user = "audio"
    case screenShare = "screen_audio"
}

struct VoiceAudioVolumeEntry: Equatable, Sendable {
    let userId: Int
    let stream: VoiceAudioStream
    let volume: Double
}

enum VoiceAudioVolumeSettings {
    static let defaultsKey = "voice.remoteAudioVolumes"
    static let defaultVolume = 1.0

    static func key(userId: Int, stream: VoiceAudioStream) -> String {
        "\(userId):\(stream.rawValue)"
    }

    static func volume(
        userId: Int,
        stream: VoiceAudioStream,
        in volumes: [String: Double]
    ) -> Double {
        clamped(volumes[key(userId: userId, stream: stream)] ?? defaultVolume)
    }

    static func clamped(_ volume: Double) -> Double {
        guard volume.isFinite else {
            return defaultVolume
        }

        return min(max(volume, 0), 1)
    }

    static func entries(in volumes: [String: Double]) -> [VoiceAudioVolumeEntry] {
        volumes.compactMap { key, volume in
            let parts = key.split(separator: ":", maxSplits: 1)

            guard
                parts.count == 2,
                let userId = Int(parts[0]),
                userId > 0,
                let stream = VoiceAudioStream(rawValue: String(parts[1]))
            else {
                return nil
            }

            return VoiceAudioVolumeEntry(
                userId: userId,
                stream: stream,
                volume: clamped(volume)
            )
        }
        .sorted {
            if $0.userId == $1.userId {
                return $0.stream.rawValue < $1.stream.rawValue
            }

            return $0.userId < $1.userId
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> [String: Double] {
        guard let stored = defaults.dictionary(forKey: defaultsKey) else {
            return [:]
        }

        var volumes: [String: Double] = [:]

        for (storedKey, value) in stored {
            guard let volume = value as? Double,
                  let entry = entries(in: [storedKey: volume]).first else {
                continue
            }

            volumes[key(userId: entry.userId, stream: entry.stream)] = entry.volume
        }

        return volumes
    }

    static func save(_ volumes: [String: Double], to defaults: UserDefaults = .standard) {
        let normalized = Dictionary(
            entries(in: volumes).map { entry in
                (key(userId: entry.userId, stream: entry.stream), entry.volume)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        defaults.set(normalized, forKey: defaultsKey)
    }
}
