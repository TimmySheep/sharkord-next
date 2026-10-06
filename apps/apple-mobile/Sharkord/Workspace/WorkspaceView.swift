import SharkordCore
import SwiftUI

/// App shell once connected: a tab bar on iPhone, a split view on iPad, and the voice
/// call bar pinned on top of everything whenever the device is in a voice channel.
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    ChannelListView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
                } detail: {
                    if let channelId = session.selectedChannelId {
                        ChannelDetailView(channelId: channelId)
                    } else {
                        Text(L10n.t("channel.empty"))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TabView {
                    ChannelListView()
                        .tabItem { Label(L10n.t("nav.channels"), systemImage: "number") }

                    MembersView()
                        .tabItem { Label(L10n.t("nav.members"), systemImage: "person.2") }

                    SettingsView()
                        .tabItem { Label(L10n.t("nav.settings"), systemImage: "gearshape") }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if voice.currentChannelId != nil {
                VoiceCallBar()
            }
        }
    }
}

/// The call bar: connection state, then the three controls. The microphone button is
/// disabled while the output is off, which is the protection the first version requires.
struct VoiceCallBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(channelName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            controlButton(
                symbol: voice.microphoneOn ? "mic.fill" : "mic.slash.fill",
                tint: voice.microphoneOn ? .green : .primary,
                disabled: !voice.canEnableMicrophone,
                action: { model.toggleMicrophone() }
            )
            .accessibilityLabel(voice.microphoneOn ? L10n.t("voice.mic.mute") : L10n.t("voice.mic.unmute"))

            controlButton(
                symbol: voice.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: voice.deafened ? .orange : .primary,
                disabled: false,
                action: { model.toggleDeafen() }
            )
            .accessibilityLabel(voice.deafened ? L10n.t("voice.output.enable") : L10n.t("voice.output.disable"))

            controlButton(
                symbol: voice.screenSharing ? "rectangle.slash.fill" : "rectangle.on.rectangle.fill",
                tint: voice.screenSharing ? .sharkordBlueSoft : .primary,
                disabled: false,
                action: { model.toggleScreenShare() }
            )
            .accessibilityLabel(voice.screenSharing ? L10n.t("voice.screen.stop") : L10n.t("voice.screen.start"))

            controlButton(
                symbol: "phone.down.fill",
                tint: .red,
                disabled: false,
                action: { model.leaveVoice() }
            )
            .accessibilityLabel(L10n.t("voice.leave"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var channelName: String {
        guard let channelId = voice.currentChannelId,
              let channel = session.channel(for: channelId) else {
            return L10n.t("voice.call")
        }
        return "#\(channel.name)"
    }

    private var statusText: String {
        if voice.deafened {
            return L10n.t("voice.status.deafened")
        }
        switch voice.callState {
        case .idle:
            return L10n.t("voice.status.idle")
        case .joining:
            return L10n.t("voice.status.joining")
        case .connecting:
            return L10n.t("voice.status.connecting")
        case .connected:
            return voice.microphoneOn ? L10n.t("voice.status.live") : L10n.t("voice.status.muted")
        case .failed:
            return L10n.t("voice.status.failed")
        }
    }

    private func controlButton(
        symbol: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.primary.opacity(0.07), in: Circle())
                .foregroundStyle(tint)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}
