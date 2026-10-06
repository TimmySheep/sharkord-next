import SharkordCore
import SwiftUI

/// App shell once connected: the floating capsule tab bar on iPhone, a split view on iPad,
/// and the call bar pinned above the tab bar whenever the device is in a voice channel.
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum Tab: Int, CaseIterable {
        case voice, channels, chat, screenShare, settings

        var title: String {
            switch self {
            case .voice: return L10n.t("nav.voice")
            case .channels: return L10n.t("nav.channels")
            case .chat: return L10n.t("nav.chat")
            case .screenShare: return L10n.t("nav.screenshare")
            case .settings: return L10n.t("nav.settings")
            }
        }

        var symbol: String {
            switch self {
            case .voice: return "waveform"
            case .channels: return "point.3.connected.trianglepath.dotted"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .screenShare: return "rectangle.on.rectangle.fill"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var tab: Tab = .channels

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitView
            } else {
                phoneContent
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            callBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sizeClass != .regular {
                tabBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
        }
        .background(BrandBackground())
    }

    private var splitView: some View {
        NavigationSplitView {
            ChannelListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            if let channelId = session.selectedChannelId {
                ChannelDetailView(channelId: channelId)
            } else {
                EmptyStateView(
                    symbol: "bubble.left.and.bubble.right",
                    title: L10n.t("chat.pickTitle"),
                    body_: L10n.t("chat.pickBody")
                )
            }
        }
    }

    private var phoneContent: some View {
        Group {
            switch tab {
            case .voice:
                VoiceTabView()
            case .channels:
                ChannelListView(
                    onOpenTextChannel: { _ in
                        tab = .chat
                    },
                    onOpenVoiceChannel: { _ in
                        tab = .voice
                    }
                )
            case .chat:
                ChatTabView()
            case .screenShare:
                ScreenshareView()
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.rawValue) { item in
                let isActive = item == tab

                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 21, weight: .semibold))

                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isActive ? SharkordTheme.accentSoft : SharkordTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        isActive ? AnyShapeStyle(SharkordTheme.pillNeutral) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// above the tab bar: the three call pills on the voice tab (and on iPad), the compact
    /// return bar on every other tab, nothing at all when the device is not in a call.
    @ViewBuilder
    private var callBar: some View {
        if voice.currentChannelId != nil {
            if tab == .voice && sizeClass != .regular {
                VoiceControlsBar()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else if sizeClass != .regular {
                BackToCallBar {
                    tab = .voice
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            } else {
                VoiceControlsBar()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
        }
    }
}

/// the three call controls: microphone pill, speaker pill and the exit button. The
/// microphone pill is disabled while the output is off, which is the protection the first
/// version requires.
struct VoiceControlsBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        HStack(spacing: 10) {
            ControlPill(
                title: voice.microphoneOn ? L10n.t("voice.action.micOff") : L10n.t("voice.action.micOn"),
                symbol: voice.microphoneOn ? "mic.fill" : "mic.slash.fill",
                background: voice.microphoneOn ? SharkordTheme.accent : SharkordTheme.pillNeutral,
                foreground: voice.microphoneOn ? .white : SharkordTheme.textPrimary,
                disabled: !voice.microphoneOn && !voice.canEnableMicrophone
            ) {
                model.toggleMicrophone()
            }

            ControlPill(
                title: voice.deafened ? L10n.t("voice.action.speakerOn") : L10n.t("voice.action.speakerOff"),
                symbol: voice.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                background: voice.deafened ? SharkordTheme.danger : SharkordTheme.accent,
                foreground: .white
            ) {
                model.toggleDeafen()
            }

            ExitButton(label: L10n.t("voice.leave")) {
                model.leaveVoice()
            }
        }
    }
}

/// compact bar shown while in a call on the non voice tabs: tap to jump back to the call.
struct BackToCallBar: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.accentSoft)

                Text(L10n.t("voice.backToCall"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textPrimary)

                Text(channelName)
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity)
            .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var channelName: String {
        guard let channelId = voice.currentChannelId,
              let channel = session.channel(for: channelId) else {
            return ""
        }
        return "#\(channel.name)"
    }
}
