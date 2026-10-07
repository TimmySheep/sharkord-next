import SharkordCore
import SwiftUI

/// Left sidebar: server menu, categories with their channels, voice channels with the
/// people in them, direct messages and the viewer's own controls.
struct SidebarView: View {
    @EnvironmentObject private var session: SharkordSession

    var onOpenSettings: () -> Void
    var onOpenServerSettings: () -> Void

    @State private var collapsed: Set<Int> = []
    @State private var showsDirectMessages = true
    @State private var showsUncategorizedChannels = true
    @State private var appliedDisclosureDefaults = false
    @State private var prompt: SidebarPrompt?
    @State private var confirmDelete: SidebarConfirm?
    @State private var newUserQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            serverHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if session.settings?.directMessagesEnabled != false {
                        directMessagesSection
                    }

                    ForEach(session.categories) { category in
                        categorySection(category)
                    }

                    uncategorizedSection
                }
                .padding(.vertical, 8)
            }

            Divider()
            userControl
        }
        .background(Theme.sidebar)
        .onAppear(perform: applyDisclosureDefaults)
        .sheet(item: $prompt) { prompt in
            PromptSheet(prompt: prompt) { self.prompt = nil }
        }
        .confirmationDialog(
            confirmDelete?.title ?? "",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button(L10n.t("deleteLabel", ns: "sidebar"), role: .destructive) {
                confirmDelete?.action()
                confirmDelete = nil
            }

            Button(L10n.t("cancel", ns: "common"), role: .cancel) {
                confirmDelete = nil
            }
        } message: {
            Text(confirmDelete?.message ?? "")
        }
    }

    // MARK: - header

    private var serverHeader: some View {
        Menu {
            if session.canManageCategories {
                Button(L10n.t("addCategory", ns: "sidebar")) {
                    prompt = SidebarPrompt(
                        title: "Create category",
                        placeholder: "Category name",
                        initial: ""
                    ) { name in
                        Task { try? await session.addCategory(name: name) }
                    }
                }
            }

            Button(L10n.t("serverSettings", ns: "sidebar")) {
                onOpenServerSettings()
            }

            Divider()

            Button(L10n.t("disconnect", ns: "sidebar"), role: .destructive) {
                session.disconnect()
            }
        } label: {
            HStack(spacing: 8) {
                Text(session.serverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - sections

    private var directMessagesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            DisclosureRow(
                title: L10n.t("directMessages", ns: "sidebar"),
                isExpanded: Binding(
                    get: { showsDirectMessages },
                    set: { showsDirectMessages = $0 }
                ),
                trailing: {
                    Button {
                        prompt = SidebarPrompt(
                            title: "New direct message",
                            placeholder: "User name",
                            initial: ""
                        ) { name in
                            openDirectMessage(named: name)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Start new conversation")
                }
            )

            if showsDirectMessages {
                ForEach(session.directMessageChannels) { channel in
                    DirectMessageRow(
                        channel: channel,
                        unread: session.unreadByChannel[channel.id] ?? 0
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await session.select(channelId: channel.id) }
                    }
                    .contextMenu {
                        Button(L10n.t("close", ns: "common")) {
                            Task { try? await session.deleteChannel(channelId: channel.id) }
                        }
                    }
                }

                if session.directMessageChannels.isEmpty {
                    Text(L10n.t("noDMsYet", ns: "sidebar"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                }
            }
        }
    }

    private func categorySection(_ category: SharkordCategory) -> some View {
        let channels = session.channels(in: category)

        return VStack(alignment: .leading, spacing: 2) {
            DisclosureRow(
                title: category.name,
                isExpanded: Binding(
                    get: { !collapsed.contains(category.id) },
                    set: { expanded in
                        if expanded {
                            collapsed.remove(category.id)
                        } else {
                            collapsed.insert(category.id)
                        }
                    }
                ),
                trailing: {
                    if session.canManageChannels {
                        Button {
                            prompt = SidebarPrompt(
                                title: "Create channel",
                                placeholder: "Channel name",
                                initial: ""
                            ) { name in
                                Task {
                                    try? await session.addChannel(type: .text, name: name, categoryId: category.id)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Create channel")
                    }
                }
            )
            .contextMenu { categoryMenu(category) }

            if !collapsed.contains(category.id) {
                ForEach(channels) { channel in
                    ChannelRow(
                        channel: channel,
                        unread: session.unreadByChannel[channel.id] ?? 0
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await session.select(channelId: channel.id) }
                    }
                    .contextMenu { channelMenu(channel) }

                    if channel.type == .voice {
                        voiceUsers(of: channel)
                    }
                }

                if channels.isEmpty {
                    Text(L10n.t("noChannels", ns: "macos"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var uncategorizedSection: some View {
        let channels = session.channels
            .filter { $0.categoryId == nil && !$0.isDm }
            .sorted { $0.position < $1.position }

        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                DisclosureRow(
                    title: L10n.t("channelsLabel", ns: "macos"),
                    isExpanded: Binding(
                        get: { showsUncategorizedChannels },
                        set: { showsUncategorizedChannels = $0 }
                    )
                ) {
                    EmptyView()
                }

                if showsUncategorizedChannels {
                    ForEach(channels) { channel in
                        ChannelRow(
                            channel: channel,
                            unread: session.unreadByChannel[channel.id] ?? 0
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await session.select(channelId: channel.id) }
                        }
                        .contextMenu { channelMenu(channel) }

                        if channel.type == .voice {
                            voiceUsers(of: channel)
                        }
                    }
                }
            }
        }
    }

    private func applyDisclosureDefaults() {
        guard !appliedDisclosureDefaults else {
            return
        }

        appliedDisclosureDefaults = true
        showsDirectMessages = session.directMessageChannels.count <= 5

        for category in session.categories where session.channels(in: category).count > 5 {
            collapsed.insert(category.id)
        }

        let uncategorizedCount = session.channels.filter { $0.categoryId == nil && !$0.isDm }.count
        showsUncategorizedChannels = uncategorizedCount <= 5
    }

    @ViewBuilder
    private func voiceUsers(of channel: SharkordChannel) -> some View {
        let users = session.voiceUsers(in: channel.id)

        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(users, id: \.user.id) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.state.micMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(entry.state.micMuted ? .red : .secondary)
                            .frame(width: 12)

                        Text(entry.user.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.leading, 30)
                    .padding(.vertical, 1)
                    .contextMenu {
                        if session.hasPermission(.moveMembers) {
                            Menu("Move to") {
                                ForEach(session.voiceChannels.filter { $0.id != channel.id }) { target in
                                    Button(target.name) {
                                        Task {
                                            try? await session.moveUser(userId: entry.user.id, to: target.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - menus

    @ViewBuilder
    private func categoryMenu(_ category: SharkordCategory) -> some View {
        if session.canManageCategories {
            Button(L10n.t("editLabel", ns: "sidebar")) {
                prompt = SidebarPrompt(
                    title: "Edit category",
                    placeholder: "Category name",
                    initial: category.name
                ) { name in
                    Task { try? await session.updateCategory(categoryId: category.id, name: name) }
                }
            }

            Button(L10n.t("deleteLabel", ns: "sidebar"), role: .destructive) {
                confirmDelete = SidebarConfirm(
                    title: "Delete category",
                    message: "Delete #\(category.name)?"
                ) {
                    Task { try? await session.deleteCategory(categoryId: category.id) }
                }
            }

            Divider()

            Button(L10n.t("moveUp", ns: "macos")) {
                moveCategory(category, by: -1)
            }

            Button(L10n.t("moveDown", ns: "macos")) {
                moveCategory(category, by: 1)
            }
        }
    }

    @ViewBuilder
    private func channelMenu(_ channel: SharkordChannel) -> some View {
        if session.canManageChannels, !channel.isDm {
            Button(L10n.t("editLabel", ns: "sidebar")) {
                prompt = SidebarPrompt(
                    title: "Edit channel",
                    placeholder: "Channel name",
                    initial: channel.name
                ) { name in
                    Task { try? await session.updateChannel(channelId: channel.id, name: name) }
                }
            }

            Button(L10n.t("deleteLabel", ns: "sidebar"), role: .destructive) {
                confirmDelete = SidebarConfirm(
                    title: "Delete channel",
                    message: "Delete #\(channel.name)?"
                ) {
                    Task { try? await session.deleteChannel(channelId: channel.id) }
                }
            }

            Divider()

            Button(L10n.t("moveUp", ns: "macos")) {
                moveChannel(channel, by: -1)
            }

            Button(L10n.t("moveDown", ns: "macos")) {
                moveChannel(channel, by: 1)
            }
        }
    }

    // MARK: - user control

    private var userControl: some View {
        HStack(spacing: 8) {
            AvatarView(user: session.ownUser, size: 30, showsPresence: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.ownUser?.name ?? "You")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(voiceStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if session.currentVoiceChannelId != nil {
                Button {
                    Task { try? await session.updateVoiceState(micMuted: true) }
                } label: {
                    Image(systemName: "mic.slash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    Task { try? await session.leaveVoice() }
                } label: {
                    Image(systemName: "phone.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("User settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var voiceStatus: String {
        if let channelId = session.currentVoiceChannelId {
            return session.channel(for: channelId)?.name ?? "Voice connected"
        }

        return "Connected"
    }

    // MARK: - actions

    private func openDirectMessage(named name: String) {
        guard let user = session.users.first(where: {
            $0.name.localizedCaseInsensitiveContains(name) && $0.id != session.ownUserId
        }) else {
            return
        }

        Task {
            try? await session.openDirectMessage(userId: user.id)
        }
    }

    private func moveCategory(_ category: SharkordCategory, by offset: Int) {
        var ids = session.categories.map(\.id)

        guard let index = ids.firstIndex(of: category.id) else {
            return
        }

        let target = index + offset

        guard ids.indices.contains(target) else {
            return
        }

        ids.swapAt(index, target)

        Task {
            try? await session.reorderCategories(categoryIds: ids)
        }
    }

    private func moveChannel(_ channel: SharkordChannel, by offset: Int) {
        guard
            let categoryId = channel.categoryId,
            let category = session.categories.first(where: { $0.id == categoryId })
        else {
            return
        }

        var ids = session.channels(in: category).map(\.id)

        guard let index = ids.firstIndex(of: channel.id) else {
            return
        }

        let target = index + offset

        guard ids.indices.contains(target) else {
            return
        }

        ids.swapAt(index, target)

        Task {
            try? await session.reorderChannels(categoryId: categoryId, channelIds: ids)
        }
    }
}

// MARK: - rows

/// A collapsible section header with an optional trailing button.
struct DisclosureRow<Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    let unread: Int

    private var typingNames: [String] {
        (session.typingByChannel[channel.id] ?? [:]).keys
            .compactMap { session.user(for: $0)?.name }
            .filter { $0 != session.ownUser?.name }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.type == .voice ? "speaker.wave.2.fill" : "number")
                .font(.system(size: 11))
                .foregroundStyle(session.selectedChannelId == channel.id ? Theme.accent : .secondary)
                .frame(width: 16)

            Text(channel.name)
                .font(.system(size: 14, weight: unread > 0 ? .semibold : .regular))
                .foregroundStyle(unread > 0 ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !typingNames.isEmpty {
                TypingDots()
            }

            if unread > 0 {
                Text("\(min(unread, 99))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(unread > 0 ? Theme.accent : .gray, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            session.selectedChannelId == channel.id
                ? Theme.elevated
                : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .padding(.horizontal, 6)
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
                .font(.system(size: 14, weight: unread > 0 ? .semibold : .regular))
                .foregroundStyle(unread > 0 ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if unread > 0 {
                Text("\(min(unread, 99))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            session.selectedChannelId == channel.id
                ? Theme.elevated
                : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .padding(.horizontal, 6)
    }
}

// MARK: - prompt

struct SidebarPrompt: Identifiable {
    let id = UUID()
    let title: String
    let placeholder: String
    let initial: String
    let onSubmit: (String) -> Void
}

struct SidebarConfirm {
    let title: String
    let message: String
    let action: () -> Void
}

/// One field dialog used for every rename and create action in the sidebar.
struct PromptSheet: View {
    let prompt: SidebarPrompt
    var onDismiss: () -> Void

    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title)
                .font(.headline)

            TextField(prompt.placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()

                Button(L10n.t("cancel", ns: "common"), role: .cancel, action: onDismiss)

                Button(L10n.t("saveButton", ns: "macos"), action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            value = prompt.initial
        }
    }

    private func submit() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return
        }

        prompt.onSubmit(trimmed)
        onDismiss()
    }
}
