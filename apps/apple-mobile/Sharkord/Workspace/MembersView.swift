import SharkordCore
import SwiftUI

/// The server member list shown at the bottom of the channels tab, with presence and role
/// names. `query` narrows it while the search field is in use.
struct MembersSection: View {
    @EnvironmentObject private var session: SharkordSession

    var query: String = ""

    private var filtered: [SharkordUser] {
        let users = query.isEmpty
            ? session.users
            : session.users.filter { $0.name.localizedCaseInsensitiveContains(query) }

        return users.sorted { lhs, rhs in
            if lhs.status == .online, rhs.status != .online {
                return true
            }
            if lhs.status != .online, rhs.status == .online {
                return false
            }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "person.2", text: "\(L10n.t("nav.members")) · \(filtered.count)")

            if filtered.isEmpty {
                Text(L10n.t("members.offline"))
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 14) {
                    ForEach(filtered) { user in
                        MemberRow(user: user)
                    }
                }
                .sharkordCard(cornerRadius: 22, padding: 16)
            }
        }
    }
}

/// one member: avatar, name, role names and a presence dot.
struct MemberRow: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser
    var showsRoles = true

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: user.name, diameter: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .lineLimit(1)

                if showsRoles {
                    Text(roleNames(for: user))
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Circle()
                .fill(user.status == .online ? SharkordTheme.success : SharkordTheme.textTertiary)
                .frame(width: 9, height: 9)
                .accessibilityLabel(user.status == .online ? L10n.t("members.online") : L10n.t("members.offline"))
        }
    }

    private func roleNames(for user: SharkordUser) -> String {
        let names = (user.roleIds ?? []).compactMap { session.role(for: $0)?.name }

        if names.isEmpty {
            return L10n.t("members.noRoles")
        }
        return names.joined(separator: ", ")
    }
}
