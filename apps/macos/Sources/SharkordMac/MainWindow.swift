import SharkordCore
import SwiftUI

/// The connected app window: channel list, the message view, an optional thread sidebar and
/// an optional member list. Laid out with plain `HStack` rather than `NavigationSplitView`
/// so the thread and member panels can both be open at once, like the web client.
struct MainWindow: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var showsMembers = true
    @State private var threadMessageId: Int?
    @State private var showsSearch = false
    @State private var settingsSection: SettingsSection?
    @State private var replyTarget: SharkordMessage?
    @State private var editing: SharkordMessage?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                onOpenSettings: { settingsSection = .profile },
                onOpenServerSettings: { settingsSection = .general }
            )
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 320)

            Divider()

            detail

            if let threadMessageId {
                Divider()

                ThreadSidebarView(messageId: threadMessageId) {
                    self.threadMessageId = nil
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            }

            if showsMembers {
                Divider()

                MemberListView()
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showsSearch) {
            SearchView { messageId, channelId in
                showsSearch = false

                Task {
                    await session.jumpTo(messageId: messageId, channelId: channelId)
                }
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(item: $settingsSection) { section in
            SettingsView(initialSection: section)
                .frame(minWidth: 720, minHeight: 480)
        }
        .onAppear {
            if session.showWelcomeDialog {
                settingsSection = .profile
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let channelId = session.selectedChannelId {
            ChannelDetailView(
                channelId: channelId,
                threadMessageId: $threadMessageId,
                replyTarget: $replyTarget,
                editing: $editing
            )
        } else {
            EmptyStateView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(session.serverName)
                .font(.headline)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if session.settings?.enableSearch != false {
                Button {
                    showsSearch = true
                } label: {
                    Label(L10n.t("searchButton", ns: "macos"), systemImage: "magnifyingglass")
                }
                .keyboardShortcut("k")
                .help("Search")
            }

            Button {
                showsMembers.toggle()
            } label: {
                Label(L10n.t("membersButton", ns: "macos"), systemImage: "person.2")
            }
            .help(showsMembers ? "Close members sidebar" : "Open members sidebar")

            Button {
                settingsSection = .general
            } label: {
                Label(L10n.t("settingsButton", ns: "macos"), systemImage: "gearshape")
            }
            .help("Settings")

            Button {
                session.disconnect()
            } label: {
                Label(L10n.t("disconnect", ns: "sidebar"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .help("Disconnect")
        }
    }
}

/// One channel's screen: the header, the message list and the composer, or the voice view.
struct ChannelDetailView: View {
    @EnvironmentObject private var session: SharkordSession

    let channelId: Int
    @Binding var threadMessageId: Int?
    @Binding var replyTarget: SharkordMessage?
    @Binding var editing: SharkordMessage?

    var body: some View {
        if let channel = session.channel(for: channelId) {
            Group {
                if channel.isDm || channel.type == .text {
                    TextChannelView(
                        channel: channel,
                        threadMessageId: $threadMessageId,
                        replyTarget: $replyTarget,
                        editing: $editing
                    )
                } else {
                    VoiceChannelView(channel: channel)
                }
            }
            .id(channel.id)
        } else {
            EmptyStateView()
        }
    }
}

struct TextChannelView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    @Binding var threadMessageId: Int?
    @Binding var replyTarget: SharkordMessage?
    @Binding var editing: SharkordMessage?

    @State private var showsPinned = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            MessageListView(
                channel: channel,
                onReply: {
                    editing = nil
                    replyTarget = $0
                },
                onEdit: {
                    replyTarget = nil
                    editing = $0
                },
                onOpenThread: { threadMessageId = $0.id }
            )

            Divider()

            Composer(
                channel: channel,
                replyTarget: $replyTarget,
                editing: $editing
            )
        }
        .background(Theme.panel)
        .task(id: channel.id) {
            replyTarget = nil
            editing = nil
            threadMessageId = nil
            await session.select(channelId: channel.id)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.isDm ? "person.fill" : "number")
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            if let topic = channel.topic, !topic.isEmpty, !channel.isDm {
                Divider().frame(height: 16)

                Text(topic)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if session.hasPermission(.pinMessages) {
                Button {
                    showsPinned.toggle()
                } label: {
                    Label(L10n.t("pinnedBadge", ns: "macos"), systemImage: "pin")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pinned messages")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .popover(isPresented: $showsPinned) {
            PinnedMessagesPanel(channel: channel) { message in
                showsPinned = false

                Task {
                    await session.jumpTo(messageId: message.id, channelId: channel.id)
                }
            }
            .frame(width: 340, height: 380)
        }
    }

    private var title: String {
        if channel.isDm {
            return session.directMessagePartner(for: channel)?.name ?? "Direct message"
        }

        return channel.name
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(L10n.t("selectChannel", ns: "macos"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }
}
