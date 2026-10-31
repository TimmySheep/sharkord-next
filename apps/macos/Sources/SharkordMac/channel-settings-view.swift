import SharkordCore
import SwiftUI

struct ChannelSettingsView: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss
    let channel: SharkordChannel?
    let initialCategoryId: Int
    @State private var name = ""
    @State private var type = ChannelType.text
    @State private var categoryId = 0
    @State private var topic = ""
    @State private var isPrivate = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t(channel == nil ? "createChannelTitle" : "editChannelTitle", ns: channel == nil ? "dialogs" : "macos"))
                .font(.headline)
            if session.canManageChannels {
                Form {
                    TextField(L10n.t("channelNamePlaceholder", ns: "dialogs"), text: $name)
                    if channel == nil {
                        Picker(L10n.t("channelType", ns: "macos"), selection: $type) {
                            Text(L10n.t("textChannel", ns: "macos")).tag(ChannelType.text)
                            Text(L10n.t("voiceChannel", ns: "macos")).tag(ChannelType.voice)
                        }
                    }
                    Picker(L10n.t("channelCategory", ns: "macos"), selection: $categoryId) {
                        if channel != nil, channel?.categoryId == nil {
                            Text(L10n.t("noCategory", ns: "macos")).tag(0)
                        }
                        ForEach(session.categories) { category in Text(category.name).tag(category.id) }
                    }
                    if channel != nil {
                        TextField(L10n.t("channelTopic", ns: "macos"), text: $topic, axis: .vertical)
                        Toggle(L10n.t("privateChannel", ns: "macos"), isOn: $isPrivate)
                    }
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                Button(L10n.t("saveButton", ns: "macos")) { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).count < 2 || (channel == nil && categoryId == 0))
            }
            if let channel, session.hasPermission(.manageChannelPermissions) {
                Divider()
                ChannelPermissionsEditor(channelId: channel.id)
            }
            HStack { Spacer(); Button(L10n.t("close", ns: "common")) { dismiss() }.disabled(saving) }
        }
        .padding(20).frame(width: 470)
        .onAppear {
            name = channel?.name ?? ""
            type = channel?.type ?? .text
            topic = channel?.topic ?? ""
            isPrivate = channel?.isPrivate ?? false
            if let channel { categoryId = channel.categoryId ?? 0 }
            else { categoryId = initialCategoryId }
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let name = name.trimmingCharacters(in: .whitespaces)
            if let channel {
                try await session.updateChannel(channelId: channel.id, name: name, topic: topic, isPrivate: isPrivate)
                if categoryId != channel.categoryId,
                   let category = session.categories.first(where: { $0.id == categoryId }) {
                    let ids = session.channels(in: category).filter { !$0.isDm && $0.id != channel.id }.map(\.id)
                    try await session.reorderChannels(categoryId: categoryId, channelIds: ids + [channel.id])
                }
            } else {
                _ = try await session.addChannel(type: type, name: name, categoryId: categoryId)
            }
            dismiss()
        } catch { errorMessage = SharkordSession.describe(error) }
    }
}

private struct ChannelPermissionsEditor: View {
    @EnvironmentObject private var session: SharkordSession
    let channelId: Int
    @State private var target = ""
    @State private var allowed: Set<ChannelPermission> = []
    @State private var loaded: ChannelPermissionsResult?
    @State private var working = false
    @State private var errorMessage: String?

    private var userId: Int? { target.hasPrefix("user:") ? Int(target.dropFirst(5)) : nil }
    private var roleId: Int? { target.hasPrefix("role:") ? Int(target.dropFirst(5)) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("headers.channel", ns: "permissions")).font(.headline)
            Picker(L10n.t("permissionTarget", ns: "macos"), selection: $target) {
                Text(L10n.t("selectPermissionTarget", ns: "macos")).tag("")
                ForEach(session.roles) { role in Text(role.name).tag("role:\(role.id)") }
                ForEach(session.users) { user in Text("\(user.name) #\(user.id)").tag("user:\(user.id)") }
            }.disabled(working)
            if !target.isEmpty {
                Text(L10n.t("permissionOverrideHelp", ns: "macos")).font(.caption).foregroundStyle(.secondary)
                ForEach(ChannelPermission.allCases, id: \.rawValue) { permission in
                    Toggle(L10n.t("channel.\(permission.rawValue)", ns: "permissions"), isOn: Binding(
                        get: { allowed.contains(permission) },
                        set: { if $0 { allowed.insert(permission) } else { allowed.remove(permission) } }
                    )).disabled(working || loaded == nil)
                }
                HStack {
                    Button(L10n.t("saveButton", ns: "macos")) { Task { await update(remove: false) } }
                    Button(L10n.t("removeOverride", ns: "macos"), role: .destructive) { Task { await update(remove: true) } }
                }.disabled(working || loaded == nil)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .task { await reload() }
        .onChange(of: target) { applySelection() }
    }

    private func applySelection() {
        guard let loaded else { allowed = []; return }
        if let userId {
            allowed = Set(loaded.userPermissions.filter { $0.userId == userId && $0.allow }.map(\.permission))
        } else if let roleId {
            allowed = Set(loaded.rolePermissions.filter { $0.roleId == roleId && $0.allow }.map(\.permission))
        } else { allowed = [] }
    }

    private func reload() async {
        do {
            loaded = try await session.getChannelPermissions(channelId: channelId)
            applySelection()
            errorMessage = nil
        } catch { errorMessage = SharkordSession.describe(error) }
    }

    private func update(remove: Bool) async {
        guard !working, userId != nil || roleId != nil else { return }
        working = true
        defer { working = false }
        do {
            if remove {
                try await session.deleteChannelPermissions(channelId: channelId, userId: userId, roleId: roleId)
            } else {
                try await session.updateChannelPermissions(.init(
                    channelId: channelId, userId: userId, roleId: roleId, permissions: Array(allowed)
                ))
            }
            await reload()
        } catch { errorMessage = SharkordSession.describe(error) }
    }
}
