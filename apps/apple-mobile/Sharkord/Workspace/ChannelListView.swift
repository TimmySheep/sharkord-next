import SharkordCore
import SwiftUI

/// the single navigation list for recent direct messages and server categories.
struct ChannelListView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let onOpenVoiceChannel: (SharkordChannel) -> Void
    let onSubmitSearch: (String) -> Void

    @State private var query = ""
    @State private var collapsedGroups: Set<String>

    private let collapsedGroupsKey = "workspace.collapsedGroups"

    init(
        onOpenVoiceChannel: @escaping (SharkordChannel) -> Void,
        onSubmitSearch: @escaping (String) -> Void
    ) {
        self.onOpenVoiceChannel = onOpenVoiceChannel
        self.onSubmitSearch = onSubmitSearch
        _collapsedGroups = State(
            initialValue: Set(UserDefaults.standard.stringArray(forKey: "workspace.collapsedGroups") ?? [])
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                channelSearchField

                if session.settings?.directMessagesEnabled != false,
                   !session.directMessages.isEmpty {
                    directMessagesSection
                }

                ForEach(session.categories) { category in
                    let channels = session.channels(in: category).filter { !$0.isDm && matches($0) }
                    if !channels.isEmpty {
                        groupSection(id: categoryKey(category.id), title: category.name) {
                            ForEach(channels) { channel in
                                channelRow(channel)
                            }
                        }
                    }
                }

                if !uncategorizedChannels.isEmpty {
                    groupSection(id: "uncategorized", title: L10n.t("nav.otherChannels")) {
                        ForEach(uncategorizedChannels) { channel in
                            channelRow(channel)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var channelSearchField: some View {
        HStack(spacing: 10) {
            Button {
                onSubmitSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SharkordTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("search.openPlaceholder"))
            TextField(L10n.t("search.openPlaceholder"), text: $query)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    onSubmitSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .accessibilityLabel(L10n.t("search.openPlaceholder"))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var directMessagesSection: some View {
        groupSection(id: "direct-messages", title: L10n.t("nav.directMessages")) {
            if recentConversations.isEmpty {
                HStack(spacing: 10) {
                    Text(L10n.t("dm.emptyTitle"))
                        .font(.subheadline)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    NavigationLink(value: WorkspaceDestination.directMessages) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.t("dm.newMessage"))
                }
            } else {
                ForEach(recentConversations) { conversation in
                    NavigationLink(value: WorkspaceDestination.channel(conversation.channelId)) {
                        conversationRow(conversation)
                    }
                    .buttonStyle(.plain)
                }
            }

            NavigationLink(value: WorkspaceDestination.directMessages) {
                HStack(spacing: 10) {
                    Image(systemName: "tray.full")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(L10n.t("dm.viewAll"))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textTertiary)
                }
                .foregroundStyle(SharkordTheme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var recentConversations: [DirectMessageConversation] {
        Array(session.directMessages
            .filter { conversation in
                guard let query = normalizedQuery else { return true }
                let name = session.user(for: conversation.userId)?.name
                    ?? session.channel(for: conversation.channelId).flatMap(session.directMessagePartner(for:))?.name
                    ?? ""
                return name.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
            .prefix(3))
    }

    private var uncategorizedChannels: [SharkordChannel] {
        session.channels
            .filter { !$0.isDm && $0.categoryId == nil && matches($0) }
            .sorted { $0.position < $1.position }
    }

    private var normalizedQuery: String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func groupSection<Content: View>(
        id: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                toggleGroup(id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsedGroups.contains(id) ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.4)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(SharkordTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(L10n.t(collapsedGroups.contains(id) ? "common.collapsed" : "common.expanded"))

            if !collapsedGroups.contains(id) {
                content()
            }
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: SharkordChannel) -> some View {
        let joined = session.isInVoice(channel.id) || voice.currentChannelId == channel.id
        let unreadCount = session.unreadByChannel[channel.id] ?? 0

        let row = HStack(spacing: 10) {
            Image(systemName: channel.type == .voice ? "waveform" : "number")
                .font(.body.weight(.semibold))
                .foregroundStyle(joined ? SharkordTheme.accentSoft : SharkordTheme.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(channel.name)
                .font(.subheadline.weight(session.selectedChannelId == channel.id ? .semibold : .regular))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)

            if channel.type == .voice {
                Text("\(session.voiceUsers(in: channel.id).count)")
                    .font(.caption)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }

            Spacer(minLength: 4)

            if unreadCount > 0 {
                Circle()
                    .fill(SharkordTheme.accentSoft)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(L10n.format("channel.unreadCount", unreadCount))
            }

            if joined {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SharkordTheme.success)
                    .accessibilityLabel(L10n.t("voice.state.joined"))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(
            session.selectedChannelId == channel.id ? SharkordTheme.field : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())

        if channel.type == .voice {
            Button {
                onOpenVoiceChannel(channel)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel(channel.name)
        } else {
            NavigationLink(value: WorkspaceDestination.channel(channel.id)) {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel(channel.name)
        }
    }

    private func conversationRow(_ conversation: DirectMessageConversation) -> some View {
        let user = session.user(for: conversation.userId)
        let channel = session.channel(for: conversation.channelId)
        let name = user?.name
            ?? channel.flatMap(session.directMessagePartner(for:))?.name
            ?? L10n.t("message.unknownAuthor")

        return HStack(spacing: 10) {
            SessionAvatarView(user: user, diameter: 34, showsStatus: true)
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if conversation.unreadCount > 0 {
                Circle()
                    .fill(SharkordTheme.accentSoft)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(L10n.format("channel.unreadCount", conversation.unreadCount))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func matches(_ channel: SharkordChannel) -> Bool {
        guard let normalizedQuery else { return true }
        return channel.name.localizedCaseInsensitiveContains(normalizedQuery)
            || channel.topic?.localizedCaseInsensitiveContains(normalizedQuery) == true
    }

    private func categoryKey(_ id: Int) -> String {
        "category-\(id)"
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
        UserDefaults.standard.set(collapsedGroups.sorted(), forKey: collapsedGroupsKey)
    }
}

struct SessionAvatarView: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser?
    let diameter: CGFloat
    var showsStatus = false

    var body: some View {
        Group {
            if let file = user?.avatar, let url = session.publicFileURL(for: file) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if showsStatus, let status = user?.status {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: max(8, diameter * 0.22), height: max(8, diameter * 0.22))
                    .overlay {
                        Circle().stroke(SharkordTheme.background, lineWidth: 1.5)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var initials: some View {
        AvatarView(
            name: user?.name ?? "?",
            diameter: diameter,
            imageURL: user?.avatar.flatMap(session.publicFileURL(for:))
        )
    }

    private func statusColor(_ status: UserStatus) -> Color {
        switch status {
        case .online:
            SharkordTheme.success
        case .idle:
            .orange
        case .offline:
            SharkordTheme.textTertiary
        }
    }
}
