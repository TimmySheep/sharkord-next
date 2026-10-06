import ActivityKit
import Foundation

/// shared by the app target and the widget extension. both reference this file directly in
/// `project.pbxproj`, so the two sides cannot drift apart on what a session looks like.
struct LiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var channelName: String
        var topic: String
        var participantCount: Int
        var isSpeaking: Bool
    }

    var serverAddress: String
}
