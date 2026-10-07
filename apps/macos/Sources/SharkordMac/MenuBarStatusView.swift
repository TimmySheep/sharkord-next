import AppKit
import SharkordCore
import SwiftUI

struct MenuBarStatusView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voiceMedia: VoiceMediaController
    @Environment(\.openWindow) private var openWindow

    private var unreadCount: Int {
        session.unreadByChannel.values.reduce(0) { $0 + max(0, $1) }
    }

    var body: some View {
        if session.phase == .connected {
            Text(session.serverName)
                .font(.headline)

            if unreadCount > 0 {
                Text(L10n.t("menuUnreadCount", ns: "macos", ["count": String(unreadCount)]))
                    .foregroundStyle(.secondary)
            }

            if let channelId = session.currentVoiceChannelId {
                let isMuted = session.voiceMap[channelId]?
                    .users[String(session.ownUserId)]?.micMuted ?? true

                Button(L10n.t(isMuted ? "unmuteMic" : "muteMic", ns: "macos")) {
                    Task {
                        do {
                            try await voiceMedia.setMicrophoneMuted(!isMuted)
                        } catch {
                            voiceMedia.presentError(error.localizedDescription, context: "microphone")
                        }
                    }
                }
                .disabled(voiceMedia.status != "connected" || !voiceMedia.canPublishAudio)
            }

            Divider()

            Button(L10n.t("menuOpenClient", ns: "macos")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(L10n.t("disconnect", ns: "sidebar"), role: .destructive) {
                session.disconnect()
            }
        } else {
            Button(L10n.t("menuOpenClient", ns: "macos")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

        Button(L10n.t("menuQuit", ns: "macos")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
