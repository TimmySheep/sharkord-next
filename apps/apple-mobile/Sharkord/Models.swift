import Foundation

enum ChannelKind: Hashable {
    case text
    case voice
}

struct ServerChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: ChannelKind
    let topic: String
    let voiceMemberIDs: [String]
}

struct ServerCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let channels: [ServerChannel]
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let authorID: String
    let body: String
    let sentAt: Date
}

struct WorkspaceMember: Identifiable, Hashable {
    let id: String
    let name: String
    let roleName: String
    let isOnline: Bool
    let isSpeaking: Bool
}
