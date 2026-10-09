import SharkordCore
import SwiftUI

/// recent direct messages and the member picker for starting a conversation.
struct DirectMessagesView: View {
    @EnvironmentObject private var session: SharkordSession
    @Binding var path: [WorkspaceDestination]

    @State private var isShowingMemberPicker = false
    @State private var query = ""

    private var recentConversations: [DirectMessageConversation] {
        session.directMessages
            .filter { conversation in
                guard !query.isEmpty else { return true }
                let userName = session.user(for: conversation.userId)?.name
                    ?? session.channel(for: conversation.channelId).flatMap(session.directMessagePartner(for:))?.name
                    ?? ""
                return userName.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    var body: some View {
        Group {
            if recentConversations.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(
                        symbol: "bubble.left.and.bubble.right",
                        title: L10n.t("dm.emptyTitle"),
                        body_: L10n.t("dm.emptyBody")
                    )
                    if session.settings?.directMessagesEnabled != false {
                        SharkordPrimaryButton(title: L10n.t("dm.newMessage"), symbol: "plus") {
                            isShowingMemberPicker = true
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandBackground())
            } else {
                conversationList
                    .background(BrandBackground())
                    .searchable(text: $query, prompt: L10n.t("dm.searchMembers"))
            }
        }
        .navigationTitle(L10n.t("dm.allConversations"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.settings?.directMessagesEnabled != false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingMemberPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.t("dm.newMessage"))
                }
            }
        }
        .sheet(isPresented: $isShowingMemberPicker) {
            NewDirectMessageView { channelId in
                path.append(.channel(channelId))
            }
        }
        .tint(SharkordTheme.accentSoft)
    }

    private var conversationList: some View {
        List {
            ForEach(recentConversations) { conversation in
                NavigationLink(value: WorkspaceDestination.channel(conversation.channelId)) {
                    conversationRow(conversation)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func conversationRow(_ conversation: DirectMessageConversation) -> some View {
        let user = session.user(for: conversation.userId)
        let channel = session.channel(for: conversation.channelId)
        let channelPartnerName = channel.map { channel in
            session.directMessagePartner(for: channel)?.name ?? channel.name
        }
        let name = user?.name ?? channelPartnerName ?? L10n.t("message.unknownAuthor")

        return HStack(spacing: 13) {
            SessionAvatarView(user: user, diameter: 48, showsStatus: true)

            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if conversation.unreadCount > 0 {
                Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(SharkordTheme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// starts a direct message with another member of the connected server.
private struct NewDirectMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SharkordSession

    let onOpenChannel: (Int) -> Void

    @State private var query = ""
    @State private var openingUserId: Int? = nil
    @State private var errorMessage = ""
    @State private var isShowingError = false

    private var filteredMembers: [SharkordUser] {
        session.users
            .filter { user in
                user.id != session.ownUserId
                    && !user.banned
                    && (query.isEmpty || user.name.localizedCaseInsensitiveContains(query))
            }
            .sorted { lhs, rhs in
                if lhs.status == .online, rhs.status != .online {
                    return true
                }
                if lhs.status != .online, rhs.status == .online {
                    return false
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredMembers.isEmpty {
                    Text(L10n.t("dm.noMembers"))
                        .font(.body)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredMembers) { user in
                        Button {
                            openConversation(with: user)
                        } label: {
                            memberRow(user)
                        }
                        .buttonStyle(.plain)
                        .disabled(openingUserId != nil)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BrandBackground())
            .searchable(text: $query, prompt: L10n.t("dm.searchMembers"))
            .navigationTitle(L10n.t("dm.newMessage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(L10n.t("dm.openFailed"), isPresented: $isShowingError) {
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(SharkordTheme.accentSoft)
    }

    private func memberRow(_ user: SharkordUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                name: user.name,
                diameter: 42,
                imageURL: user.avatar.flatMap(session.publicFileURL(for:))
            )

            Text(user.name)
                .font(.body.weight(.medium))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if openingUserId == user.id {
                ProgressView()
                    .tint(SharkordTheme.accentSoft)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textTertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func openConversation(with user: SharkordUser) {
        guard openingUserId == nil else {
            return
        }

        openingUserId = user.id

        Task {
            do {
                let channelId = try await session.openDirectMessage(userId: user.id)
                onOpenChannel(channelId)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }

            openingUserId = nil
        }
    }
}
