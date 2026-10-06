import SharkordCore
import SwiftUI

/// Right sidebar: the member list, with a profile card per member carrying the moderation
/// and role actions the web client puts in its user popover and mod view.
struct MemberListView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var selected: SharkordUser?

    private var sorted: [SharkordUser] {
        session.users.sorted { lhs, rhs in
            if lhs.banned != rhs.banned {
                return !lhs.banned
            }

            let lhsRank = statusRank(lhs.status)
            let rhsRank = statusRank(rhs.status)

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("membersHeader", ns: "sidebar", ["count": session.users.count]))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sorted) { user in
                        MemberRow(user: user)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = user
                            }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Theme.sidebar)
        .popover(item: $selected) { user in
            UserProfileCard(user: user)
                .frame(width: 300)
        }
    }

    private func statusRank(_ status: UserStatus?) -> Int {
        switch status {
        case .online:
            return 0
        case .idle:
            return 1
        case .offline, .none:
            return 2
        }
    }
}

struct MemberRow: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(user: user, size: 26, showsPresence: true)

            Text(user.name)
                .font(.system(size: 12.5, weight: user.id == session.ownUserId ? .semibold : .regular))
                .strikethrough(user.banned)
                .foregroundStyle(user.banned ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if user.banned {
                Image(systemName: "nosign")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

/// Profile card: identity, roles, bio and the actions available on this member.
struct UserProfileCard: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser

    @State private var errorMessage: String?
    @State private var showsRolePicker = false

    private var isOwn: Bool {
        user.id == session.ownUserId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Theme.color(for: user)
                    .frame(height: 56)

                AvatarView(user: user, size: 54)
                    .padding(.leading, 12)
                    .offset(y: 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(user.name)
                    .font(.system(size: 15, weight: .bold))
                    .strikethrough(user.banned)

                if user.banned {
                    Label(L10n.t("bannedBadge", ns: "common"), systemImage: "nosign")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }

                roleBadges

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Text(L10n.t("memberSince", ns: "common", ["date": L10n.date(Date(timeIntervalSince1970: Double(user.createdAt) / 1000), style: .medium)]))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }

                Divider()

                actions
            }
            .padding(12)
            .padding(.top, 22)
        }
        .background(Theme.panel)
    }

    @ViewBuilder
    private var roleBadges: some View {
        let roles = (user.roleIds ?? []).compactMap { session.role(for: $0) }

        if !roles.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(roles) { role in
                    HStack(spacing: 4) {
                        Text(role.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: role.color) ?? .secondary)

                        if session.canManageUsers, !isOwn, role.id != ProtocolDefaults.ownerRoleId {
                            Button {
                                Task {
                                    try? await session.removeRole(userId: user.id, roleId: role.id)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.elevated, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.settings?.directMessagesEnabled != false, !isOwn, !user.banned {
                Button {
                    Task {
                        try? await session.openDirectMessage(userId: user.id)
                    }
                } label: {
                    Label(L10n.t("openDirectMessages", ns: "sidebar"), systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }

            if session.canManageUsers, !isOwn {
                Divider()

                if session.isOwner() {
                    rolePicker
                }

                HStack(spacing: 6) {
                    Button(L10n.t("kickBtn", ns: "settings")) {
                        Task {
                            try? await session.kickUser(userId: user.id, reason: nil)
                        }
                    }

                    if user.banned {
                        Button(L10n.t("unbanBtn", ns: "settings")) {
                            Task {
                                try? await session.unbanUser(userId: user.id)
                            }
                        }
                    } else {
                        Button(L10n.t("banBtn", ns: "settings"), role: .destructive) {
                            Task {
                                try? await session.banUser(userId: user.id, reason: nil)
                            }
                        }
                    }

                    Button(L10n.t("deleteBtn", ns: "settings"), role: .destructive) {
                        Task {
                            try? await session.deleteUser(userId: user.id, wipe: false)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private var rolePicker: some View {
        let assignable = session.roles.filter { role in
            !(user.roleIds ?? []).contains(role.id)
        }

        if !assignable.isEmpty {
            Menu("Assign role") {
                ForEach(assignable) { role in
                    Button(role.name) {
                        Task {
                            try? await session.addRole(userId: user.id, roleId: role.id)
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
