import SharkordCore
import SwiftUI

/// Roster grouped by presence, matching how the web client orders members.
struct MemberListView: View {
    @EnvironmentObject private var session: SharkordSession

    private var online: [SharkordUser] {
        session.users.filter { $0.status == .online || $0.status == .idle }
    }

    private var offline: [SharkordUser] {
        session.users.filter { $0.status != .online && $0.status != .idle }
    }

    var body: some View {
        List {
            if !online.isEmpty {
                Section {
                    ForEach(online) { MemberRow(user: $0) }
                } header: {
                    Eyebrow(text: "Online — \(online.count)")
                }
            }

            if !offline.isEmpty {
                Section {
                    ForEach(offline) { MemberRow(user: $0) }
                } header: {
                    Eyebrow(text: "Offline — \(offline.count)")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct MemberRow: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser

    private var roleColor: Color? {
        let roleIds = Set(user.roleIds ?? [])
        let role = session.roles.first { $0.isDefault == false && roleIds.contains($0.id) }

        guard let role else {
            return nil
        }

        return Color(hex: role.color)
    }

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(user: user, size: 28, showsPresence: true)

            Text(user.name)
                .font(.system(size: 13))
                .foregroundStyle(roleColor ?? .primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if user.id != session.ownUserId {
                Button {
                    Task {
                        try? await session.openDirectMessage(userId: user.id)
                    }
                } label: {
                    Label("Message", systemImage: "bubble.left")
                }
            }
        }
    }
}
