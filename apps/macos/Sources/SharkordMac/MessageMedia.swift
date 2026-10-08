import Foundation

enum MessageMediaType: String, Equatable {
    case audio
    case video

    init?(fileExtension: String) {
        let normalized = fileExtension.lowercased().hasPrefix(".")
            ? fileExtension.lowercased()
            : ".\(fileExtension.lowercased())"

        switch normalized {
        case ".mp4", ".mkv", ".mov", ".avi", ".wmv", ".flv", ".webm", ".mpeg", ".mpg", ".3gp":
            self = .video
        case ".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".alac":
            self = .audio
        default:
            return nil
        }
    }
}

struct MessageMediaReference: Identifiable, Equatable {
    let type: MessageMediaType
    let url: URL

    var id: String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let normalizedURL = components?.url?.absoluteString ?? url.absoluteString
        return "\(type.rawValue):\(normalizedURL)"
    }

    static func file(fileExtension: String, url: URL?) -> MessageMediaReference? {
        guard let url, let type = MessageMediaType(fileExtension: fileExtension) else {
            return nil
        }

        return MessageMediaReference(type: type, url: url)
    }

    static func metadata(
        kind: String,
        mediaType: String?,
        url: URL?
    ) -> MessageMediaReference? {
        guard kind != "open_graph",
              let url,
              let mediaType,
              let type = MessageMediaType(rawValue: mediaType)
        else {
            return nil
        }

        return MessageMediaReference(type: type, url: url)
    }

    static func deduplicated(_ references: [MessageMediaReference]) -> [MessageMediaReference] {
        var seen = Set<String>()

        return references.filter { seen.insert($0.id).inserted }
    }
}
