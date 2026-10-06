import Combine
import Foundation
import SharkordCore
import SwiftUI

/// The single observable object the screens read. It owns the shared `SharkordSession`
/// (server state and signalling), the `VoiceEngine` (media), and the small amount of UI
/// state that is genuinely app local: language, banners and the Dynamic Island activity.
/// Changes from the session and the voice engine are forwarded here, so views observe one
/// object and still refresh on every server update.
@MainActor
final class AppModel: ObservableObject {
    let session: SharkordSession
    let voice: VoiceEngine

    @Published var language: String = L10n.current
    @Published var banner: String?
    @Published private(set) var liveActivityRunning = false

    private let liveActivityController = LiveActivityController()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let session = SharkordSession()
        self.session = session
        self.voice = VoiceEngine(session: session)

        session.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        voice.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // a remote producer appearing anywhere in the joined channel is the cue to open
        // (or drop) consumers; the engine reconciles the full set
        session.$producersByChannel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.voice.reconcileProducers()
                }
            }
            .store(in: &cancellables)

        // being moved or kicked out of the voice channel clears the local call
        session.$voiceMap
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.syncVoiceWithServer()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - connection

    func connect(host: String, identity: String, password: String, serverPassword: String) async {
        banner = nil
        await session.connect(
            host: host,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        )

        if case .failed(let message) = session.phase {
            banner = message
        }
    }

    func disconnect() {
        Task { await voice.leave() }
        session.disconnect()
    }

    // MARK: - navigation

    func selectChannel(_ channelId: Int) {
        Task {
            await session.select(channelId: channelId)
            session.markAsRead(channelId)
        }
    }

    // MARK: - language

    func setLanguage(_ code: String) {
        L10n.current = code
        language = code
    }

    // MARK: - voice

    func joinVoice(_ channelId: Int) {
        banner = nil

        Task {
            await voice.join(channelId: channelId)
            await syncVoiceWithServer()
            updateLiveActivity()
        }
    }

    func leaveVoice() {
        Task {
            await voice.leave()
            updateLiveActivity()
        }
    }

    func toggleMicrophone() {
        let target = !voice.microphoneOn

        Task {
            do {
                try await voice.setMicrophoneEnabled(target)
            } catch {
                banner = error.localizedDescription
            }
        }
    }

    func toggleDeafen() {
        let target = !voice.deafened

        Task {
            do {
                try await voice.setDeafened(target)
            } catch {
                banner = error.localizedDescription
            }
        }
    }

    func toggleScreenShare() {
        Task {
            do {
                if voice.screenSharing {
                    await voice.stopScreenShare()
                } else {
                    try await voice.startScreenShare()
                }
            } catch {
                banner = error.localizedDescription
            }
        }
    }

    /// Keeps the local call in step with the server: the user being moved by a moderator
    /// or removed from the channel ends the local session exactly like the web client.
    private func syncVoiceWithServer() async {
        guard let channelId = voice.currentChannelId else {
            return
        }

        if session.currentVoiceChannelId != channelId {
            await voice.leave()
            banner = L10n.t("voice.notice.movedOrRemoved")
            updateLiveActivity()
        }
    }

    // MARK: - Dynamic Island

    private func updateLiveActivity() {
        if let channelId = voice.currentChannelId, let channel = session.channel(for: channelId) {
            let participants = session.voiceUsers(in: channelId).count
            let topic = channel.topic ?? L10n.t("voice.liveActivity.topic")

            if liveActivityController.isRunning {
                Task {
                    await liveActivityController.update(
                        channelName: channel.name,
                        topic: topic,
                        participantCount: participants,
                        isSpeaking: voice.microphoneOn
                    )
                }
            } else {
                liveActivityController.start(
                    serverAddress: session.serverName,
                    channelName: channel.name,
                    topic: topic,
                    participantCount: participants
                )
            }
            liveActivityRunning = true
        } else if liveActivityController.isRunning {
            liveActivityRunning = false
            Task { await liveActivityController.end() }
        }
    }

    /// Kept for the settings screen: shows the activity with sample data before any call.
    func startPreviewLiveActivity() {
        let started = liveActivityController.start(
            serverAddress: serverDisplayName,
            channelName: L10n.t("voice.liveActivity.previewChannel"),
            topic: L10n.t("voice.liveActivity.previewTopic"),
            participantCount: 3
        )
        liveActivityRunning = started
    }

    func stopPreviewLiveActivity() {
        liveActivityRunning = false
        Task { await liveActivityController.end() }
    }

    // MARK: - display helpers

    var serverDisplayName: String {
        if !session.serverName.isEmpty {
            return session.serverName
        }
        return session.serverBaseURL?.host() ?? "Sharkord"
    }

    var isConnected: Bool {
        if case .connected = session.phase {
            return true
        }
        return false
    }
}
