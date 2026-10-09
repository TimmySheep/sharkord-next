import SharkordCore
import SwiftUI

enum WorkspaceDestination: Hashable {
    case channel(Int)
    case voiceChat(Int)
    case directMessages
    case settings
}

/// one navigation stack keeps channel, message and settings routes together.
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    @State private var path: [WorkspaceDestination] = []
    @State private var isSearchPresented = false
    @State private var globalSearchQuery = ""
    @State private var searchPresentationId = UUID()
    @State private var voicePreviewChannel: SharkordChannel?
    @State private var keyboardVisible = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                ChannelListView(
                    onOpenVoiceChannel: { channel in
                        if voice.currentChannelId == channel.id {
                            path = [.channel(channel.id)]
                        } else {
                            voicePreviewChannel = channel
                        }
                    },
                    onSubmitSearch: { query in
                        globalSearchQuery = query
                        searchPresentationId = UUID()
                        isSearchPresented = true
                    }
                )
                    .navigationTitle(model.serverDisplayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if session.settings?.directMessagesEnabled != false,
                           session.directMessages.isEmpty {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    path.append(.directMessages)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .accessibilityLabel(L10n.t("dm.newMessage"))
                            }
                        }
                    }
                    .navigationDestination(for: WorkspaceDestination.self) { destination in
                        switch destination {
                        case .channel(let channelId):
                            ChannelDetailView(channelId: channelId)
                        case .voiceChat(let channelId):
                            ChannelDetailView(channelId: channelId, showsVoiceChatInitially: true)
                        case .directMessages:
                            DirectMessagesView(path: $path)
                        case .settings:
                            SettingsView()
                        }
                    }
                    .sheet(isPresented: $isSearchPresented) {
                        NavigationStack {
                            MessageSearchView(
                                initialQuery: globalSearchQuery,
                                onOpenMessage: openSearchMessage
                            )
                            .id(searchPresentationId)
                        }
                    }
            }
            if !isShowingVoiceRoom && !keyboardVisible {
                bottomDock
            }
        }
        .tint(SharkordTheme.accentSoft)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .background(BrandBackground())
        .sheet(item: $voicePreviewChannel) { channel in
            VoiceChannelPreviewSheet(
                channelId: channel.id,
                onJoin: {
                    voicePreviewChannel = nil
                    model.joinVoice(channel.id)
                },
                onOpenChat: {
                    voicePreviewChannel = nil
                    path = [.voiceChat(channel.id)]
                }
            )
            .presentationDetents([.fraction(0.42), .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear(perform: navigateToVoiceCallIfRequested)
        .onChange(of: voice.currentChannelId) { _, channelId in
            if channelId == nil && isShowingVoiceRoom {
                path = []
            }
        }
        .onChange(of: model.pendingLiveActivityCallNavigationId) { _, _ in
            navigateToVoiceCallIfRequested()
        }
    }

    private var bottomDock: some View {
        VStack(spacing: 0) {
            if let channelId = statusChannelId {
                voiceConnectionBar(channelId: channelId)
            }
            userStatusBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(SharkordTheme.background)
    }

    private var statusChannelId: Int? {
        if let channelId = voice.currentChannelId {
            return channelId
        }
        if case .failed = voice.callState {
            return voice.lastCallChannelId
        }
        return nil
    }

    private var isShowingVoiceRoom: Bool {
        guard case let .channel(channelId) = path.last else {
            return false
        }
        return session.channel(for: channelId)?.type == .voice
    }

    private var userStatusBar: some View {
        HStack(spacing: 8) {
            SessionAvatarView(user: session.ownUser, diameter: 40, showsStatus: true)

            Text(session.ownUser?.name ?? L10n.t("message.unknownAuthor"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Button {
                path.append(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("nav.settings"))
        }
        .padding(.horizontal, 8)
        .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func voiceConnectionBar(channelId: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                path = [.channel(channelId)]
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(callStateColor)
                        .frame(width: 8, height: 8)
                    Text(L10n.format("voice.connectionStatus", callStateTitle, session.channel(for: channelId)?.name ?? ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.toggleMicrophone()
            } label: {
                Image(systemName: voice.microphoneOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(voice.microphoneOn ? SharkordTheme.textPrimary : SharkordTheme.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(voice.callState != .connected)
            .opacity(voice.callState == .connected ? 1 : 0.45)
            .accessibilityLabel(L10n.t(voice.microphoneOn ? "voice.action.micOff" : "voice.action.micOn"))

            Button {
                model.leaveVoice()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SharkordTheme.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("voice.leave"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 6)
    }

    private var callStateTitle: String {
        switch voice.callState {
        case .idle, .connected:
            return L10n.t("voice.state.live")
        case .joining:
            return L10n.t("voice.state.joining")
        case .connecting:
            return L10n.t("voice.state.connecting")
        case .failed:
            return L10n.t("voice.state.failed")
        }
    }

    private var callStateColor: Color {
        switch voice.callState {
        case .idle, .joining, .connecting:
            return SharkordTheme.accentSoft
        case .connected:
            return SharkordTheme.success
        case .failed:
            return SharkordTheme.danger
        }
    }

    private func openSearchMessage(_ channelId: Int, _ messageId: Int) {
        path = [.channel(channelId)]

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

    private func navigateToVoiceCallIfRequested() {
        guard model.pendingLiveActivityCallNavigationId != nil,
              let channelId = voice.currentChannelId
        else {
            return
        }

        path = [.channel(channelId)]
        model.pendingLiveActivityCallNavigationId = nil
    }
}
