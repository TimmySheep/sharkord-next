import SharkordCore
import SwiftUI

/// Everyone on the server, with presence and role names.
struct MembersView: View {
    @EnvironmentObject private var session: SharkordSession

    private var online: [SharkordUser] {
        session.users.filter { $0.status == .online }
    }

    private var offline: [SharkordUser] {
        session.users.filter { $0.status != .online }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("\(L10n.t("members.online")) · \(online.count)") {
                    ForEach(online) { user in
                        memberRow(user)
                    }
                }

                if !offline.isEmpty {
                    Section("\(L10n.t("members.offline")) · \(offline.count)") {
                        ForEach(offline) { user in
                            memberRow(user)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("nav.members"))
        }
    }

    private func memberRow(_ user: SharkordUser) -> some View {
        HStack(spacing: 11) {
            AvatarView(name: user.name, diameter: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.body.weight(.medium))

                Text(roleNames(for: user))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Circle()
                .fill(user.status == .online ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    private func roleNames(for user: SharkordUser) -> String {
        let names = (user.roleIds ?? []).compactMap { session.role(for: $0)?.name }

        if names.isEmpty {
            return L10n.t("members.noRoles")
        }
        return names.joined(separator: ", ")
    }
}
