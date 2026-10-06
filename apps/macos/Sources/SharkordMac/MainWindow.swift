import SharkordCore
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsMembers = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
        } detail: {
            if let channelId = session.selectedChannelId {
                ChannelDetailView(channelId: channelId)
            } else {
                EmptyStateView()
            }
        }
        .inspector(isPresented: $showsMembers) {
            MemberListView()
                .inspectorColumnWidth(min: 200, ideal: 240, max: 300)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text(session.serverName)
                    .font(.headline)
            }

            ToolbarItemGroup {
                Button {
                    showsMembers.toggle()
                } label: {
                    Label("Members", systemImage: "person.2")
                }

                Button {
                    session.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var session: SharkordSession

    private var selection: Binding<Int?> {
        Binding(
            get: { session.selectedChannelId },
            set: { newValue in
                guard let newValue else {
                    return
                }

                Task { await session.select(channelId: newValue) }
            }
        )
    }

    private var uncategorized: [SharkordChannel] {
        session.channels
            .filter { $0.categoryId == nil && !$0.isDm }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        List(selection: selection) {
            Section {
                serverHeader
            }

            ForEach(session.categories) { category in
                let channels = session.channels(in: category)

                if !channels.isEmpty {
                    Section {
                        ForEach(channels) { channel in
                            ChannelRow(channel: channel, unread: session.unreadByChannel[channel.id] ?? 0)
                                .tag(channel.id)
                        }
                    } header: {
                        Eyebrow(text: category.name)
                    }
                }
            }

            if !uncategorized.isEmpty {
                Section {
                    ForEach(uncategorized) { channel in
                        ChannelRow(channel: channel, unread: session.unreadByChannel[channel.id] ?? 0)
                            .tag(channel.id)
                    }
                } header: {
                    Eyebrow(text: "Channels")
                }
            }

            if !session.directMessageChannels.isEmpty {
                Section {
                    ForEach(session.directMessageChannels) { channel in
                        DirectMessageRow(channel: channel, unread: session.unreadByChannel[channel.id] ?? 0)
                            .tag(channel.id)
                    }
                } header: {
                    Eyebrow(text: "Direct messages")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var serverHeader: some View {
        HStack(spacing: 10) {
            AvatarView(user: session.ownUser, size: 34, showsPresence: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.ownUser?.name ?? "You")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ChannelRow: View {
    let channel: SharkordChannel
    let unread: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.type == .voice ? "speaker.wave.2.fill" : "number")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(channel.name)
                .font(.system(size: 13, weight: unread > 0 ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule())
            }
        }
    }
}

struct DirectMessageRow: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    let unread: Int

    var body: some View {
        let partner = session.directMessagePartner(for: channel)

        HStack(spacing: 8) {
            AvatarView(user: partner, size: 20, showsPresence: true)

            Text(partner?.name ?? "Direct message")
                .font(.system(size: 13, weight: unread > 0 ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule())
            }
        }
    }
}

struct ChannelDetailView: View {
    @EnvironmentObject private var session: SharkordSession

    let channelId: Int

    var body: some View {
        if let channel = session.channel(for: channelId) {
            // DM channels are stored as `VOICE` on the server (so a call can reuse the
            // channel later) but render as text.
            if channel.isDm || channel.type == .text {
                TextChannelView(channel: channel)
            } else {
                VoiceChannelView(channel: channel)
            }
        } else {
            EmptyStateView()
        }
    }
}

struct TextChannelView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel

    @State private var replyTarget: SharkordMessage?
    @State private var editing: SharkordMessage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MessageListView(
                channel: channel,
                onReply: { replyTarget = $0 },
                onEdit: { editing = $0 }
            )
            Divider()
            Composer(channel: channel, replyTarget: $replyTarget, editing: $editing)
        }
        .background(Theme.panel)
        .task(id: channel.id) {
            replyTarget = nil
            editing = nil
            await session.select(channelId: channel.id)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.isDm ? "person.fill" : "number")
                .foregroundStyle(.secondary)

            Text(headerTitle)
                .font(.headline)

            if let topic = channel.topic, !topic.isEmpty, !channel.isDm {
                Divider().frame(height: 16)

                Text(topic)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        if channel.isDm {
            return session.directMessagePartner(for: channel)?.name ?? "Direct message"
        }

        return channel.name
    }
}

struct VoiceChannelView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)

            Text(channel.name)
                .font(.title2.bold())

            Eyebrow(text: "Voice channel")

            Text("Native voice (mediasoup) is the next milestone. Text is fully wired.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Select a channel")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }
}
