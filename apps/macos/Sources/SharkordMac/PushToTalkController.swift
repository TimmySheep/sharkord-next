import AppKit
import Combine
import CoreGraphics
import SharkordCore

@MainActor
final class PushToTalkController: ObservableObject {
    @Published private(set) var permissionAvailable = false
    @Published private(set) var permissionRequired = false

    private weak var session: SharkordSession?
    private weak var voiceMedia: VoiceMediaController?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false
    private var shouldRestoreMuted = false
    private var mediaTask: Task<Void, Never>?
    private let keyCode: UInt16 = 105

    func bind(to session: SharkordSession, voiceMedia: VoiceMediaController) {
        self.session = session
        self.voiceMedia = voiceMedia
        refreshPermission()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            removeMonitors()
            releaseKey()
            permissionRequired = false
            return
        }

        permissionAvailable = CGPreflightListenEventAccess()

        guard permissionAvailable else {
            permissionRequired = true
            _ = CGRequestListenEventAccess()
            return
        }

        permissionRequired = false
        installMonitors()
    }

    func refreshPermission() {
        permissionAvailable = CGPreflightListenEventAccess()

        if permissionAvailable {
            permissionRequired = false
        }
    }

    func restoreEnabled(_ enabled: Bool) {
        guard enabled else {
            return
        }

        refreshPermission()

        if permissionAvailable {
            installMonitors()
        } else {
            permissionRequired = true
        }
    }

    func retryAfterPermissionChange() {
        refreshPermission()

        if permissionAvailable {
            installMonitors()
        }
    }

    private func installMonitors() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }

            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == keyCode else {
            return
        }

        if event.type == .keyDown {
            guard !event.isARepeat else {
                return
            }

            pressKey()
        } else if event.type == .keyUp {
            releaseKey()
        }
    }

    private func pressKey() {
        guard !isPressed,
              let session,
              let channelId = session.currentVoiceChannelId,
              let voiceMedia,
              voiceMedia.status == "connected",
              voiceMedia.canPublishAudio else {
            return
        }

        isPressed = true
        shouldRestoreMuted = session.voiceMap[channelId]?
            .users[String(session.ownUserId)]?.micMuted ?? true

        if shouldRestoreMuted {
            enqueueMicrophoneState(muted: false, voiceMedia: voiceMedia)
        }
    }

    private func releaseKey() {
        guard isPressed else {
            return
        }

        isPressed = false

        if shouldRestoreMuted, let voiceMedia {
            enqueueMicrophoneState(muted: true, voiceMedia: voiceMedia)
        }

        shouldRestoreMuted = false
    }

    private func enqueueMicrophoneState(muted: Bool, voiceMedia: VoiceMediaController) {
        let previousTask = mediaTask
        mediaTask = Task { [weak self] in
            await previousTask?.value

            do {
                try await voiceMedia.setMicrophoneMuted(muted)
            } catch {
                self?.voiceMedia?.presentError(error, context: "microphone")
            }
        }
    }
}
