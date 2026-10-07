import SharkordCore
import SwiftUI

/// app shell with native tabs for channels, direct messages and settings.
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    private enum Tab: Hashable {
        case channels
        case directMessages
        case settings
    }

    @State private var selectedTab: Tab = .channels
    @State private var channelPath: [Int] = []
    @State private var isSearchPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $channelPath) {
                ChannelListView()
                    .navigationDestination(for: Int.self) { channelId in
                        ChannelDetailView(channelId: channelId)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isSearchPresented = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel(L10n.t("search.title"))
                        }
                    }
            }
            .tabItem {
                Label(L10n.t("nav.channels"), systemImage: "point.3.connected.trianglepath.dotted")
            }
            .tag(Tab.channels)

            DirectMessagesView()
                .tabItem {
                    Label(L10n.t("nav.directMessages"), systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Tab.directMessages)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(L10n.t("nav.settings"), systemImage: "slider.horizontal.3")
            }
            .tag(Tab.settings)
        }
        .tint(SharkordTheme.accentSoft)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(SharkordTheme.background, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            callBar
        }
        .background(BrandBackground())
        .sheet(isPresented: $isSearchPresented) {
            NavigationStack {
                MessageSearchView(onOpenMessage: openSearchMessage)
            }
        }
    }

    /// keeps call controls available without adding another destination to the tab bar.
    @ViewBuilder
    private var callBar: some View {
        if let channelId = voice.currentChannelId {
            if selectedTab == .channels && channelPath.last == channelId {
                VoiceControlsBar()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else {
                BackToCallBar {
                    selectedTab = .channels
                    channelPath = [channelId]
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    private func openSearchMessage(_ channelId: Int, _ messageId: Int) {
        selectedTab = .channels
        channelPath = [channelId]

        Task {
            do {
                let message = try await session.getMessage(messageId: messageId)
                if let parentMessageId = message.parentMessageId {
                    await session.jumpTo(messageId: parentMessageId, channelId: channelId)
                    model.pendingMessageNavigation = PendingMessageNavigation(
                        channelId: channelId,
                        messageId: parentMessageId
                    )
                    model.pendingThreadParentId = parentMessageId
                } else {
                    await session.jumpTo(messageId: message.id, channelId: channelId)
                    model.pendingMessageNavigation = PendingMessageNavigation(
                        channelId: channelId,
                        messageId: message.id
                    )
                }
            } catch {
                model.banner = error.localizedDescription
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
        return channel.name
    }
}
