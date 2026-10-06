import SwiftUI

/// roster grouped by presence. the grouping lives here rather than in `AppModel` because it is a
/// presentation concern and nothing else needs it.
struct MembersView: View {
    @ObservedObject var model: AppModel

    private var online: [WorkspaceMember] {
        model.members.filter(\.isOnline)
    }

    private var offline: [WorkspaceMember] {
        model.members.filter { !$0.isOnline }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OfflineNotice()

                memberGroup(title: "在线 · \(online.count)", members: online, dimmed: false)
                memberGroup(title: "离线 · \(offline.count)", members: offline, dimmed: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("成员")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func memberGroup(title: String, members: [WorkspaceMember], dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: title)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(members) { member in
                    memberRow(member, dimmed: dimmed)
                }
            }
        }
    }

    private func memberRow(_ member: WorkspaceMember, dimmed: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: member.name, diameter: 36, isSpeaking: member.isSpeaking)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if member.isSpeaking {
                    Text("正在说话")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 8)

            Text(member.roleName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 52)
        .opacity(dimmed ? 0.55 : 1)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
