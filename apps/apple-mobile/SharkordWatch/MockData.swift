import Foundation

/// Offline stand-in data for the skeleton (phase 1). Phase 2 replaces these types with
/// the shared session models; the screens only depend on these field names.

struct WatchParticipant: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var isSpeaking = false
    var micMuted = false
}

struct WatchChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let topic: String
    var participants: [WatchParticipant]
}

enum MockData {
    static let channels: [WatchChannel] = [
        WatchChannel(
            id: "gaming",
            name: "Gaming",
            topic: "开黑对讲",
            participants: [
                WatchParticipant(name: "Alice", isSpeaking: true),
                WatchParticipant(name: "Bob"),
                WatchParticipant(name: "Tim", micMuted: true)
            ]
        ),
        WatchChannel(
            id: "general",
            name: "General",
            topic: "日常闲聊",
            participants: [
                WatchParticipant(name: "Alice"),
                WatchParticipant(name: "Tim")
            ]
        ),
        WatchChannel(
            id: "family",
            name: "Family",
            topic: "家庭频道",
            participants: [
                WatchParticipant(name: "Mom"),
                WatchParticipant(name: "Dad", micMuted: true)
            ]
        )
    ]
}
