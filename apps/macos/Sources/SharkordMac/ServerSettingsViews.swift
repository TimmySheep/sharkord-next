import AppKit
import SharkordCore
import SwiftUI

/// Server identity and access settings.
struct GeneralServerSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var name = ""
    @State private var description = ""
    @State private var password = ""
    @State private var allowNewUsers = true
    @State private var directMessages = true
    @State private var enableSearch = true
    @State private var enablePlugins = true
    @State private var simulcast = false
    @State private var showWelcomeDialog = true
    @State private var onlyAskForPasswordOnFirstJoin = false
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("serverInfoTitle", ns: "settings"),
            subtitle: L10n.t("serverInfoDesc", ns: "settings"),
            onSave: save
        ) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsField(label: L10n.t("nameLabel", ns: "settings")) {
                    TextField(L10n.t("namePlaceholder", ns: "settings"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }

                SettingsField(label: L10n.t("descriptionLabel", ns: "settings")) {
                    TextEditor(text: $description)
                        .frame(minHeight: 70, maxHeight: 110)
                }

                SettingsField(
                    label: L10n.t("serverPasswordLabel", ns: "settings"),
                    help: L10n.t("passwordDesc", ns: "settings")
                ) {
                    HStack(spacing: 8) {
                        SecureField(L10n.t("serverPasswordPlaceholder", ns: "settings"), text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)

                        Button(L10n.t("deleteBtn", ns: "settings")) {
                            password = ""
                        }
                    }
                }

                Toggle(L10n.t("onlyAskForPasswordOnFirstJoinLabel", ns: "settings"), isOn: $onlyAskForPasswordOnFirstJoin)
                Text(L10n.t("onlyAskForPasswordOnFirstJoinDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("allowNewUsersLabel", ns: "settings"), isOn: $allowNewUsers)
                Text(L10n.t("allowNewUsersDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("directMessagesEnabledLabel", ns: "settings"), isOn: $directMessages)
                Text(L10n.t("directMessagesEnabledDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("searchEnabledLabel", ns: "settings"), isOn: $enableSearch)
                Text(L10n.t("searchEnabledDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("pluginsLabel", ns: "settings"), isOn: $enablePlugins)
                Text(L10n.t("pluginsManageDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("simulcastLabel", ns: "settings"), isOn: $simulcast)
                Text(L10n.t("simulcastDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("showWelcomeDialogLabel", ns: "settings"), isOn: $showWelcomeDialog)
                Text(L10n.t("showWelcomeDialogDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? .red : .green)
                }
            }
            .toggleStyle(.switch)
        }
        .task {
            guard let settings = try? await session.getSettings() else {
                return
            }

            name = settings.name
            description = settings.description ?? ""
            password = settings.password ?? ""
            allowNewUsers = settings.allowNewUsers ?? true
            directMessages = settings.directMessagesEnabled ?? true
            enableSearch = settings.enableSearch ?? true
            enablePlugins = settings.enablePlugins ?? true
            simulcast = settings.webRtcSimulcastEnabled ?? false
            showWelcomeDialog = settings.showWelcomeDialog ?? true
            onlyAskForPasswordOnFirstJoin = settings.onlyAskForPasswordOnFirstJoin ?? false
        }
    }

    private func save() {
        Task {
            do {
                try await session.updateSettings([
                    "name": .string(name),
                    "description": .string(description),
                    "password": password.isEmpty ? .null : .string(password),
                    "allowNewUsers": .bool(allowNewUsers),
                    "directMessagesEnabled": .bool(directMessages),
                    "enableSearch": .bool(enableSearch),
                    "enablePlugins": .bool(enablePlugins),
                    "webRtcSimulcastEnabled": .bool(simulcast),
                    "showWelcomeDialog": .bool(showWelcomeDialog),
                    "onlyAskForPasswordOnFirstJoin": .bool(onlyAskForPasswordOnFirstJoin)
                ])

                statusMessage = L10n.t("settingsUpdated", ns: "settings")
                isError = false
            } catch {
                statusMessage = SharkordSession.describe(error)
                isError = true
            }
        }
    }
}

/// Storage limits, disk usage and per-plugin storage.
struct StorageSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var result: StorageSettingsResult?
    @State private var uploadEnabled = true
    @State private var maxFileSize = 0
    @State private var maxFilesPerMessage = 10
    @State private var dmFileSharing = true
    @State private var quotaPerUser = 0
    @State private var overflowAction = "delete"
    @State private var signedUrls = true
    @State private var imageOptimization = true
    @State private var statusMessage: String?

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("storageTitle", ns: "settings"),
            subtitle: L10n.t("storageDesc", ns: "settings"),
            onSave: save
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if let metrics = result?.diskMetrics {
                    metricsSection(metrics)
                }

                Toggle(L10n.t("allowUploadsLabel", ns: "settings"), isOn: $uploadEnabled)
                Text(L10n.t("allowUploadsDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                SettingsField(label: L10n.t("maxFileSizeLabel", ns: "settings")) {
                    TextField("", value: $maxFileSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                SettingsField(label: L10n.t("maxFilesPerMessageLabel", ns: "settings")) {
                    Stepper("\(maxFilesPerMessage)", value: $maxFilesPerMessage, in: 0...20)
                        .frame(width: 180)
                }

                Toggle(L10n.t("allowFileSharingInDMsLabel", ns: "settings"), isOn: $dmFileSharing)
                Text(L10n.t("allowFileSharingInDMsDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                SettingsField(label: L10n.t("quotaPerUserLabel", ns: "settings"), help: L10n.t("quotaHelp", ns: "settings")) {
                    TextField("", value: $quotaPerUser, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                SettingsField(label: L10n.t("overflowActionLabel", ns: "settings")) {
                    Picker("", selection: $overflowAction) {
                        Text(L10n.t("overflowDeleteOldFiles", ns: "settings")).tag("delete")
                        Text(L10n.t("overflowPreventUploads", ns: "settings")).tag("prevent")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Toggle(L10n.t("signedUrlsLabel", ns: "settings"), isOn: $signedUrls)
                Text(L10n.t("signedUrlsDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("imageOptimizationLabel", ns: "settings"), isOn: $imageOptimization)
                Text(L10n.t("imageOptimizationDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if let plugins = result?.pluginStorage, !plugins.isEmpty {
                    pluginUsage(plugins)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }
            .toggleStyle(.switch)
        }
        .task {
            result = try? await session.getStorageSettings()

            if let settings = result?.storageSettings {
                uploadEnabled = settings.storageUploadEnabled ?? true
                maxFileSize = settings.storageUploadMaxFileSize ?? 0
                maxFilesPerMessage = settings.storageMaxFilesPerMessage ?? 10
                dmFileSharing = settings.storageFileSharingInDirectMessages ?? true
                quotaPerUser = settings.storageSpaceQuotaByUser ?? 0
                overflowAction = settings.storageOverflowAction ?? "delete"
                signedUrls = settings.storageSignedUrlsEnabled ?? true
                imageOptimization = settings.storageImageOptimizationEnabled ?? true
            }
        }
    }

    private func metricsSection(_ metrics: DiskMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: L10n.t("diskUsage", ns: "settings"))

            Text("\(bytes(metrics.totalSpace)) \(L10n.t("diskTotalSpace", ns: "settings"))")
            Text("\(bytes(metrics.sharkordUsedSpace)) \(L10n.t("diskSharkordUsed", ns: "settings"))")
            Text("\(bytes(metrics.freeSpace)) \(L10n.t("diskAvailableSpace", ns: "settings"))")
        }
        .font(.system(size: 11.5))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 14)
    }

    private func pluginUsage(_ plugins: [PluginStorageInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: L10n.t("pluginStorageTitle", ns: "settings"))

            ForEach(plugins, id: \.pluginId) { plugin in
                HStack {
                    Text(plugin.pluginId)
                        .font(.system(size: 11.5, design: .monospaced))

                    Spacer()

                    Text(bytes(plugin.usedSpace))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 14)
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func save() {
        Task {
            do {
                try await session.updateSettings([
                    "storageUploadEnabled": .bool(uploadEnabled),
                    "storageUploadMaxFileSize": .int(maxFileSize),
                    "storageMaxFilesPerMessage": .int(maxFilesPerMessage),
                    "storageFileSharingInDirectMessages": .bool(dmFileSharing),
                    "storageSpaceQuotaByUser": .int(quotaPerUser),
                    "storageOverflowAction": .string(overflowAction),
                    "storageSignedUrlsEnabled": .bool(signedUrls),
                    "storageImageOptimizationEnabled": .bool(imageOptimization)
                ])

                statusMessage = L10n.t("storageSettingsUpdated", ns: "settings")
            } catch {
                statusMessage = SharkordSession.describe(error)
            }
        }
    }
}

// MARK: - users

/// Server member administration: search, inspect and moderate.
struct UsersSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var users: [SharkordAdminUser] = []
    @State private var query = ""
    @State private var selected: SharkordAdminUser?
    @State private var detail: UserDetail?
    @State private var errorMessage: String?

    private var filtered: [SharkordAdminUser] {
        guard !query.isEmpty else {
            return users
        }

        return users.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.identity ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("usersTitle", ns: "settings"),
            subtitle: L10n.t("usersDesc", ns: "settings")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(L10n.t("searchUsersPlaceholder", ns: "settings"), text: $query)
                        .textFieldStyle(.plain)

                    Button(L10n.t("refreshBtn", ns: "settings")) {
                        Task { await load() }
                    }
                }
                .padding(10)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                ForEach(filtered) { user in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.color(for: nil))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text(String(user.name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.system(size: 12, weight: .medium))

                            Text(user.identity ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if user.banned {
                            Text(L10n.t("bannedBadge", ns: "common"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                        }

                        Button(L10n.t("detailsTitle", ns: "settings")) {
                            Task {
                                selected = user
                                detail = try? await session.getUserInfo(userId: user.id)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .contextMenu {
                        Button(L10n.t("kickBtn", ns: "settings")) {
                            Task {
                                try? await session.kickUser(userId: user.id, reason: nil)
                                await load()
                            }
                        }

                        if user.banned {
                            Button(L10n.t("unbanBtn", ns: "settings")) {
                                Task {
                                    try? await session.unbanUser(userId: user.id)
                                    await load()
                                }
                            }
                        } else {
                            Button(L10n.t("banBtn", ns: "settings"), role: .destructive) {
                                Task {
                                    try? await session.banUser(userId: user.id, reason: nil)
                                    await load()
                                }
                            }
                        }

                        Button(L10n.t("deleteBtn", ns: "settings"), role: .destructive) {
                            Task {
                                try? await session.deleteUser(userId: user.id, wipe: false)
                                await load()
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selected) { user in
            UserDetailSheet(user: user, detail: detail)
                .frame(width: 460, height: 480)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        users = (try? await session.getAllUsers()) ?? []
        errorMessage = users.isEmpty ? nil : nil
    }
}

/// One member's full record: identity, roles, storage and their recent logins.
struct UserDetailSheet: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    let user: SharkordAdminUser
    let detail: UserDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(user.name)
                    .font(.title3.bold())

                Spacer()

                Button(L10n.t("close", ns: "common")) {
                    dismiss()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    row(L10n.t("userIdLabel", ns: "settings"), value: "\(user.id)")
                    row(L10n.t("identityDetailLabel", ns: "settings"), value: user.identity ?? "-")
                    row(
                        L10n.t("joinedServerLabel", ns: "settings"),
                        value: Date(timeIntervalSince1970: Double(user.createdAt) / 1000)
                            .formatted(date: .abbreviated, time: .shortened)
                    )

                    if let lastLogin = user.lastLoginAt {
                        row(
                            L10n.t("lastActiveLabel", ns: "settings"),
                            value: Date(timeIntervalSince1970: Double(lastLogin) / 1000)
                                .formatted(date: .abbreviated, time: .shortened)
                        )
                    }

                    row(
                        L10n.t("passwordTitle", ns: "settings"),
                        value: user.passwordSet == false
                            ? L10n.t("secretUnsetPlaceholder", ns: "settings")
                            : L10n.t("secretSetPlaceholder", ns: "settings")
                    )

                    if let detail {
                        Divider()

                        Eyebrow(text: L10n.t("rolesSection", ns: "settings"))

                        HStack(spacing: 6) {
                            ForEach(detail.user.roleIds?.compactMap { session.role(for: $0) } ?? []) { role in
                                Text(role.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color(hex: role.color) ?? .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.elevated, in: Capsule())
                            }
                        }

                        Divider()

                        Eyebrow(text: L10n.t("modViewStorageTitle", ns: "settings"))

                        row(
                            L10n.t("modViewStorageUsed", ns: "settings"),
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(detail.storage.usedStorage),
                                countStyle: .file
                            )
                        )

                        row(
                            L10n.t("modViewStorageFiles", ns: "settings"),
                            value: "\(detail.storage.fileCount)"
                        )

                        Divider()

                        Eyebrow(text: L10n.t("ipAddressLabel", ns: "settings"))

                        ForEach(detail.logins) { login in
                            HStack {
                                Text(login.ip ?? "-")
                                    .font(.system(size: 11, design: .monospaced))

                                Text(login.location ?? "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(
                                    Date(timeIntervalSince1970: Double(login.createdAt) / 1000),
                                    style: .relative
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11.5))
                .textSelection(.enabled)
        }
    }
}

// MARK: - roles

/// Role list plus a permission editor, matching the web client's role editor tabs.
struct RolesSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var roles: [SharkordRole] = []
    @State private var selected: SharkordRole?
    @State private var name = ""
    @State private var color = "#1447E6"
    @State private var permissions: Set<String> = []
    @State private var quotaOverride = false
    @State private var quota = 0
    @State private var statusMessage: String?

    var body: some View {
        SettingsSectionLayout(title: L10n.t("rolesTitle", ns: "settings")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(roles) { role in
                        Button {
                            select(role)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: role.color) ?? .gray)
                                    .frame(width: 10, height: 10)

                                Text(role.name)
                                    .font(.system(size: 12, weight: selected?.id == role.id ? .semibold : .regular))

                                Spacer()

                                if role.isDefault {
                                    Text(L10n.t("roleDefault", ns: "dialogs"))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(
                                selected?.id == role.id ? Theme.elevated : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        Button(L10n.t("addRoleTooltip", ns: "settings")) {
                            Task {
                                if let roleId = try? await session.addRole() {
                                    roles = (try? await session.getAllRoles()) ?? []
                                    select(roles.first { $0.id == roleId })
                                }
                            }
                        }

                        Button(L10n.t("deleteBtn", ns: "settings"), role: .destructive) {
                            guard let selected else {
                                return
                            }

                            Task {
                                try? await session.deleteRole(roleId: selected.id)
                                self.selected = nil
                                roles = (try? await session.getAllRoles()) ?? []
                            }
                        }
                        .disabled(selected == nil)
                    }
                    .padding(.top, 6)
                }
                .frame(width: 220)

                Divider()

                if let selected {
                    editor(selected)
                } else {
                    Text(L10n.t("selectRoleToEdit", ns: "settings"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
        }
        .task {
            roles = (try? await session.getAllRoles()) ?? []
        }
    }

    private func editor(_ role: SharkordRole) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsField(label: L10n.t("roleNameLabel", ns: "settings")) {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                SettingsField(label: L10n.t("roleColorLabel", ns: "settings")) {
                    HStack(spacing: 8) {
                        TextField("", text: $color)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)

                        ColorPicker("", selection: Binding(
                            get: { Color(hex: color) ?? .gray },
                            set: { color = $0.hexString }
                        ))
                        .labelsHidden()
                    }
                }

                Eyebrow(text: L10n.t("permissionsTab", ns: "settings"))

                ForEach(Permission.allCases, id: \.self) { permission in
                    Toggle(
                        L10n.t("server.\(permission.rawValue)", ns: "permissions"),
                        isOn: Binding(
                            get: { permissions.contains(permission.rawValue) },
                            set: { enabled in
                                if enabled {
                                    permissions.insert(permission.rawValue)
                                } else {
                                    permissions.remove(permission.rawValue)
                                }
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                }

                Divider().padding(.vertical, 12)

                Toggle(L10n.t("roleStorageOverrideLabel", ns: "settings"), isOn: $quotaOverride)
                Text(L10n.t("roleStorageOverrideDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if quotaOverride {
                    SettingsField(label: L10n.t("roleStorageQuotaLabel", ns: "settings")) {
                        TextField("", value: $quota, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }

                Button(L10n.t("saveChanges", ns: "settings")) {
                    save(role)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }

    private func select(_ role: SharkordRole?) {
        selected = role
        name = role?.name ?? ""
        color = role?.color ?? "#1447E6"
        permissions = Set(role?.permissions ?? [])
        quotaOverride = role?.storageQuotaOverrideEnabled ?? false
        quota = role?.storageSpaceQuota ?? 0
    }

    private func save(_ role: SharkordRole) {
        Task {
            do {
                try await session.updateRole(RoleUpdate(
                    roleId: role.id,
                    name: name,
                    color: color,
                    permissions: Array(permissions).sorted(),
                    storageQuotaOverrideEnabled: quotaOverride,
                    storageSpaceQuota: quota
                ))

                roles = (try? await session.getAllRoles()) ?? []
                select(roles.first { $0.id == role.id })
                statusMessage = L10n.t("roleUpdated", ns: "settings")
            } catch {
                statusMessage = SharkordSession.describe(error)
            }
        }
    }
}

// MARK: - emojis

struct EmojisSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var emojis: [SharkordEmoji] = []
    @State private var query = ""
    @State private var errorMessage: String?

    private var filtered: [SharkordEmoji] {
        guard !query.isEmpty else {
            return emojis
        }

        return emojis.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        SettingsSectionLayout(title: L10n.t("emojiTitle", ns: "settings")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField(L10n.t("searchEmojisPlaceholder", ns: "settings"), text: $query)
                        .textFieldStyle(.roundedBorder)

                    Button(L10n.t("uploadEmojiBtn", ns: "settings")) {
                        upload()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                if filtered.isEmpty {
                    Text(L10n.t("noCustomEmojisYet", ns: "settings"))
                        .foregroundStyle(.secondary)
                }

                ForEach(filtered) { emoji in
                    HStack(spacing: 10) {
                        if let file = emoji.file, let url = session.publicFileURL(for: file) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFit()
                                }
                            }
                            .frame(width: 28, height: 28)
                        }

                        Text(":\(emoji.name):")
                            .font(.system(size: 12, design: .monospaced))

                        Spacer()

                        Text(emoji.user?.name ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Button(L10n.t("editLabel", ns: "sidebar")) {
                            rename(emoji)
                        }
                        .buttonStyle(.borderless)

                        Button(L10n.t("deleteEmojiBtn", ns: "settings"), role: .destructive) {
                            Task {
                                try? await session.deleteEmoji(emojiId: emoji.id)
                                emojis = (try? await session.getAllEmojis()) ?? []
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .task {
            emojis = (try? await session.getAllEmojis()) ?? []
        }
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else {
            return
        }

        Task {
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else {
                    continue
                }

                guard
                    let fileId = try? await session.uploadAttachment(
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: "image/png"
                    )
                else {
                    continue
                }

                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: " ", with: "_")

                try? await session.addEmojis([EmojiCreateEntry(fileId: fileId, name: name)])
            }

            emojis = (try? await session.getAllEmojis()) ?? []
        }
    }

    private func rename(_ emoji: SharkordEmoji) {
        let alert = NSAlert()
        alert.messageText = L10n.t("editEmojiTitle", ns: "settings")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = emoji.name
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else {
            return
        }

        Task {
            try? await session.updateEmoji(emojiId: emoji.id, name: name)
            emojis = (try? await session.getAllEmojis()) ?? []
        }
    }
}

// MARK: - invites

struct InvitesSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var invites: [SharkordInvite] = []
    @State private var maxUses = 0
    @State private var expiresInDays = 7
    @State private var copiedCode: String?

    var body: some View {
        SettingsSectionLayout(title: L10n.t("invitesTitle", ns: "settings")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Stepper(
                        "\(L10n.t("maxUsesLabel", ns: "dialogs")): \(maxUses == 0 ? L10n.t("inviteNever", ns: "settings") : "\(maxUses)")",
                        value: $maxUses,
                        in: 0...100
                    )

                    Stepper(
                        "\(L10n.t("expiresInLabel", ns: "dialogs")): \(expiresInDays) d",
                        value: $expiresInDays,
                        in: 0...365
                    )

                    Spacer()

                    Button(L10n.t("createInviteBtn", ns: "settings")) {
                        Task {
                            _ = try? await session.createInvite(InviteCreate(
                                maxUses: maxUses == 0 ? nil : maxUses,
                                expiresAt: expiresInDays == 0
                                    ? nil
                                    : Int(Date().timeIntervalSince1970 * 1000)
                                        + expiresInDays * 86_400_000
                            ))

                            invites = (try? await session.getAllInvites()) ?? []
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if invites.isEmpty {
                    Text(L10n.t("noInvitesFound", ns: "settings"))
                        .foregroundStyle(.secondary)
                }

                ForEach(invites) { invite in
                    HStack(spacing: 10) {
                        Text(invite.code)
                            .font(.system(size: 12, design: .monospaced))

                        Text(invite.uses == 0 && invite.maxUses == nil
                            ? L10n.t("inviteDefault", ns: "settings")
                            : "\(invite.uses)/\(invite.maxUses.map(String.init) ?? "∞")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if copiedCode == invite.code {
                            Text(L10n.t("inviteCopied", ns: "settings"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.green)
                        }

                        Button(L10n.t("copyInviteLink", ns: "settings")) {
                            copy(invite)
                        }
                        .buttonStyle(.borderless)

                        Button(L10n.t("deleteBtn", ns: "settings"), role: .destructive) {
                            Task {
                                try? await session.deleteInvite(inviteId: invite.id)
                                invites = (try? await session.getAllInvites()) ?? []
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .task {
            invites = (try? await session.getAllInvites()) ?? []
        }
    }

    private func copy(_ invite: SharkordInvite) {
        let link = session.inviteURL(code: invite.code) ?? invite.code

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)

        copiedCode = invite.code
    }
}

// MARK: - plugins

struct PluginsSettingsView: View {
    var body: some View {
        PluginManagementView()
    }
}

// MARK: - updates

struct UpdatesSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var info: UpdateInfo?
    @State private var updating = false
    @State private var statusMessage: String?

    var body: some View {
        SettingsSectionLayout(title: L10n.t("updatesTitle", ns: "settings")) {
            VStack(alignment: .leading, spacing: 12) {
                if let info {
                    row(L10n.t("currentVersionLabel", ns: "settings"), value: info.currentVersion)
                    row(L10n.t("latestVersionLabel", ns: "settings"), value: info.latestVersion)

                    if info.hasUpdate {
                        Label(L10n.t("updateAvailableDesc", ns: "settings"), systemImage: "arrow.down.circle")
                            .foregroundStyle(.orange)

                        Button(L10n.t("updateServerBtn", ns: "settings")) {
                            Task {
                                updating = true
                                defer { updating = false }

                                do {
                                    try await session.updateServer()
                                    statusMessage = L10n.t("serverUpdateInitiated", ns: "common")
                                } catch {
                                    statusMessage = SharkordSession.describe(error)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updating || !info.canUpdate)
                    } else {
                        Label(L10n.t("upToDateDesc", ns: "settings"), systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                    }

                    if !info.canUpdate {
                        Text(L10n.t("updatesNotSupportedDesc", ns: "settings"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            info = try? await session.getUpdate()
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}
