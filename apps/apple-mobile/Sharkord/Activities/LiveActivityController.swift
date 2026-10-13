import ActivityKit
import Foundation

/// owns the Live Activity that represents a voice session in the Dynamic Island and on the lock screen.
@MainActor
final class LiveActivityController {
    private var activity: Activity<LiveActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool {
        activity != nil
    }

    @discardableResult
    func start(
        serverAddress: String,
        channelName: String,
        topic: String,
        participantCount: Int
    ) -> Bool {
        guard isSupported, activity == nil else { return false }

        let state = LiveActivityAttributes.ContentState(
            channelName: channelName,
            topic: topic,
            participantCount: participantCount,
            isSpeaking: false
        )
        let content = ActivityContent(state: state, staleDate: nil)
        let attributes = LiveActivityAttributes(serverAddress: serverAddress)

        guard let started = try? Activity.request(attributes: attributes, content: content) else {
            return false
        }

        activity = started
        return true
    }

    func update(
        channelName: String,
        topic: String,
        participantCount: Int,
        isSpeaking: Bool
    ) async {
        guard let activity else { return }

        let state = LiveActivityAttributes.ContentState(
            channelName: channelName,
            topic: topic,
            participantCount: participantCount,
            isSpeaking: isSpeaking
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        guard let activity else { return }
        self.activity = nil

        await activity.end(nil, dismissalPolicy: .default)
    }
}
