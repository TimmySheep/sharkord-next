import PhotosUI
import SharkordCore
import SwiftUI
import UIKit

private enum ServerAdminSection: String, CaseIterable, Identifiable {
    case channels
    case general
    case storage
    case users
    case roles
    case emojis
    case invites
    case plugins
    case updates

    var id: String { rawValue }

    var permission: Permission {
        switch self {
        case .channels: .manageChannels
        case .general: .manageSettings
        case .storage: .manageStorage
        case .users: .manageUsers
        case .roles: .manageRoles
        case .emojis: .manageEmojis
        case .invites: .manageInvites
        case .plugins: .managePlugins
        case .updates: .manageUpdates
        }
    }

    var title: String {
        L10n.t("admin.\(rawValue)")
    }

    var symbol: String {
        switch self {
        case .channels: "number"
        case .general: "gearshape"
        case .storage: "externaldrive"
        case .users: "person.2"
        case .roles: "person.badge.key"
        case .emojis: "face.smiling"
        case .invites: "envelope"
        case .plugins: "puzzlepiece.extension"
        case .updates: "arrow.down.circle"
        }
    }

    @MainActor
    func isAvailable(to session: SharkordSession) -> Bool {
        if self == .channels {
            return session.hasPermission(.manageChannels) || session.hasPermission(.manageCategories)
        }
        return session.hasPermission(permission)
    }
}

struct ServerManagementView: View {
    @EnvironmentObject private var session: SharkordSession

    private var availableSections: [ServerAdminSection] {
        ServerAdminSection.allCases.filter { $0.isAvailable(to: session) }
    }

    var body: some View {
        List {
            ForEach(availableSections) { section in
                NavigationLink {
                    ServerAdminDetailView(section: section)
                } label: {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        }
        .navigationTitle(L10n.t("admin.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ServerAdminDetailView: View {
    let section: ServerAdminSection

    @ViewBuilder
    var body: some View {
        switch section {
        case .channels:
            ChannelsServerAdminView()
        case .general:
            GeneralServerAdminView()
        case .storage:
            StorageServerAdminView()
        case .users:
            UsersServerAdminView()
        case .roles:
            RolesServerAdminView()
        case .emojis:
            EmojisServerAdminView()
        case .invites:
            InvitesServerAdminView()
        case .plugins:
            PluginsServerAdminView()
        case .updates:
            UpdatesServerAdminView()
        }
    }
}

private struct ChannelsServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var activeSheet: ChannelAdminSheet?
    @State private var categoryToDelete: SharkordCategory?
    @State private var channelToDelete: SharkordChannel?
    @State private var status: String?

    private var canManageChannels: Bool { session.hasPermission(.manageChannels) }
    private var canManageCategories: Bool { session.hasPermission(.manageCategories) }

    var body: some View {
        List {
            if canManageCategories {
                Section {
                    Button {
                        activeSheet = .newCategory
                    } label: {
                        Label(L10n.t("admin.addCategory"), systemImage: "plus")
                    }
                }
            }

            ForEach(session.categories) { category in
                Section {
                    ForEach(session.channels(in: category).filter { !$0.isDm }) { channel in
                        HStack(spacing: 10) {
                            Image(systemName: channel.type == .voice ? "speaker.wave.2" : "number")
                                .foregroundStyle(SharkordTheme.accentSoft)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                if let topic = channel.topic, !topic.isEmpty {
                                    Text(topic)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if canManageChannels {
                                Menu {
                                    Button(L10n.t("admin.editChannel")) {
                                        activeSheet = .editChannel(channel)
                                    }
                                    Button(role: .destructive) {
                                        channelToDelete = channel
                                    } label: {
                                        Label(L10n.t("common.delete"), systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(L10n.t("admin.channelActions"))
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(category.name)
                        Spacer()
                        if canManageChannels {
                            Button {
                                activeSheet = .newChannel(categoryId: category.id)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(L10n.t("admin.addChannel"))
                        }
                        if canManageCategories {
                            Menu {
                                Button(L10n.t("admin.editCategory")) {
                                    activeSheet = .editCategory(category)
                                }
                                Button(role: .destructive) {
                                    categoryToDelete = category
                                } label: {
                                    Label(L10n.t("admin.deleteCategory"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .accessibilityLabel(L10n.t("admin.categoryActions"))
                        }
                    }
                }
            }

            if session.categories.isEmpty {
                Text(L10n.t("admin.noCategories"))
                    .foregroundStyle(.secondary)
            }
            if let status {
                AdminStatusText(text: status)
            }
        }
        .navigationTitle(L10n.t("admin.channels"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .newCategory:
                    CategoryAdminEditor(category: nil, onError: showError)
                case .newChannel(let categoryId):
                    ChannelAdminEditor(channel: nil, categoryId: categoryId, onError: showError)
                case .editCategory(let category):
                    CategoryAdminEditor(category: category, onError: showError)
                case .editChannel(let channel):
                    ChannelAdminEditor(channel: channel, categoryId: channel.categoryId ?? 0, onError: showError)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            L10n.t("admin.deleteCategoryTitle"),
            isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteCategory() }
            Button(L10n.t("common.cancel"), role: .cancel) { categoryToDelete = nil }
        }
        .confirmationDialog(
            L10n.t("admin.deleteChannelTitle"),
            isPresented: Binding(get: { channelToDelete != nil }, set: { if !$0 { channelToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteChannel() }
            Button(L10n.t("common.cancel"), role: .cancel) { channelToDelete = nil }
        }
    }

    private func deleteCategory() {
        guard let category = categoryToDelete else { return }
        categoryToDelete = nil
        Task {
            do { try await session.deleteCategory(categoryId: category.id) }
            catch { showError(SharkordSession.describe(error)) }
        }
    }

    private func deleteChannel() {
        guard let channel = channelToDelete else { return }
        channelToDelete = nil
        Task {
            do { try await session.deleteChannel(channelId: channel.id) }
            catch { showError(SharkordSession.describe(error)) }
        }
    }

    private func showError(_ message: String) {
        status = message
    }
}

private enum ChannelAdminSheet: Identifiable {
    case newCategory
    case newChannel(categoryId: Int)
    case editCategory(SharkordCategory)
    case editChannel(SharkordChannel)

    var id: String {
        switch self {
        case .newCategory: "new-category"
        case .newChannel(let categoryId): "new-channel-\(categoryId)"
        case .editCategory(let category): "edit-category-\(category.id)"
        case .editChannel(let channel): "edit-channel-\(channel.id)"
        }
    }
}

private struct CategoryAdminEditor: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss
    let category: SharkordCategory?
    let onError: (String) -> Void
    @State private var name: String
    @State private var isSaving = false

    init(category: SharkordCategory?, onError: @escaping (String) -> Void) {
        self.category = category
        self.onError = onError
        _name = State(initialValue: category?.name ?? "")
    }

    var body: some View {
        Form {
            TextField(L10n.t("admin.categoryName"), text: $name)
        }
        .navigationTitle(L10n.t(category == nil ? "admin.addCategory" : "admin.editCategory"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.t("common.save"), action: save)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                if let category {
                    try await session.updateCategory(categoryId: category.id, name: name)
                } else {
                    _ = try await session.addCategory(name: name)
                }
                dismiss()
            } catch { onError(SharkordSession.describe(error)) }
        }
    }
}

private struct ChannelAdminEditor: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss
    let channel: SharkordChannel?
    let categoryId: Int
    let onError: (String) -> Void
    @State private var name: String
    @State private var topic: String
    @State private var type: ChannelType
    @State private var isPrivate: Bool
    @State private var isSaving = false

    init(channel: SharkordChannel?, categoryId: Int, onError: @escaping (String) -> Void) {
        self.channel = channel
        self.categoryId = categoryId
        self.onError = onError
        _name = State(initialValue: channel?.name ?? "")
        _topic = State(initialValue: channel?.topic ?? "")
        _type = State(initialValue: channel?.type ?? .text)
        _isPrivate = State(initialValue: channel?.isPrivate ?? false)
    }

    var body: some View {
        Form {
            TextField(L10n.t("admin.channelName"), text: $name)
            if channel == nil {
                Picker(L10n.t("admin.channelType"), selection: $type) {
                    Text(L10n.t("admin.textChannel")).tag(ChannelType.text)
                    Text(L10n.t("admin.voiceChannel")).tag(ChannelType.voice)
                }
            }
            if type == .text {
                TextField(L10n.t("admin.channelTopic"), text: $topic, axis: .vertical)
                    .lineLimit(2...5)
            }
            Toggle(L10n.t("admin.privateChannel"), isOn: $isPrivate)
        }
        .navigationTitle(L10n.t(channel == nil ? "admin.addChannel" : "admin.editChannel"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.t("common.save"), action: save)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                if let channel {
                    try await session.updateChannel(
                        channelId: channel.id,
                        name: name,
                        topic: topic,
                        isPrivate: isPrivate
                    )
                } else {
                    let channelId = try await session.addChannel(type: type, name: name, categoryId: categoryId)
                    if isPrivate || (type == .text && !topic.isEmpty) {
                        try await session.updateChannel(
                            channelId: channelId,
                            topic: type == .text ? topic : nil,
                            isPrivate: isPrivate
                        )
                    }
                }
                dismiss()
            } catch { onError(SharkordSession.describe(error)) }
        }
    }
}

private struct GeneralServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var name = ""
    @State private var description = ""
    @State private var password = ""
    @State private var allowNewUsers = true
    @State private var directMessages = true
    @State private var searchEnabled = true
    @State private var pluginsEnabled = true
    @State private var simulcastEnabled = false
    @State private var welcomeEnabled = true
    @State private var firstJoinPasswordOnly = false
    @State private var selectedLogo: PhotosPickerItem?
    @State private var removesLogo = false
    @State private var isSaving = false
    @State private var status: String?

    var body: some View {
        Form {
            Section(L10n.t("admin.serverIdentity")) {
                TextField(L10n.t("admin.name"), text: $name)
                TextField(L10n.t("admin.description"), text: $description, axis: .vertical)
                    .lineLimit(3...6)
                SecureField(L10n.t("admin.serverPassword"), text: $password)
                HStack(spacing: 12) {
                    if !removesLogo,
                       let logo = session.serverInfo?.logo,
                       let url = session.publicFileURL(for: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 84, height: 56)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(width: 84, height: 56)
                    }
                    PhotosPicker(selection: $selectedLogo, matching: .images) {
                        Label(L10n.t("admin.chooseLogo"), systemImage: "photo")
                    }
                    .onChange(of: selectedLogo) { _, _ in removesLogo = false }
                    if session.serverInfo?.logo != nil, !removesLogo {
                        Button(L10n.t("admin.removeLogo"), role: .destructive) {
                            selectedLogo = nil
                            removesLogo = true
                        }
                    }
                }
            }

            Section(L10n.t("admin.access")) {
                Toggle(L10n.t("admin.allowNewUsers"), isOn: $allowNewUsers)
                Toggle(L10n.t("admin.firstJoinPasswordOnly"), isOn: $firstJoinPasswordOnly)
                Toggle(L10n.t("admin.directMessages"), isOn: $directMessages)
                Toggle(L10n.t("admin.search"), isOn: $searchEnabled)
                Toggle(L10n.t("admin.pluginsEnabled"), isOn: $pluginsEnabled)
                Toggle(L10n.t("admin.simulcast"), isOn: $simulcastEnabled)
                Toggle(L10n.t("admin.welcome"), isOn: $welcomeEnabled)
            }

            if let status {
                AdminStatusText(text: status)
            }
        }
        .navigationTitle(L10n.t("admin.general"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("common.save"), action: save)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let settings = try await session.getSettings()
            name = settings.name
            description = settings.description ?? ""
            password = settings.password ?? ""
            allowNewUsers = settings.allowNewUsers ?? true
            firstJoinPasswordOnly = settings.onlyAskForPasswordOnFirstJoin ?? false
            directMessages = settings.directMessagesEnabled ?? true
            searchEnabled = settings.enableSearch ?? true
            pluginsEnabled = settings.enablePlugins ?? true
            simulcastEnabled = settings.webRtcSimulcastEnabled ?? false
            welcomeEnabled = settings.showWelcomeDialog ?? true
        } catch {
            status = SharkordSession.describe(error)
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await session.updateSettings([
                    "name": .string(name),
                    "description": .string(description),
                    "password": password.isEmpty ? .null : .string(password),
                    "allowNewUsers": .bool(allowNewUsers),
                    "onlyAskForPasswordOnFirstJoin": .bool(firstJoinPasswordOnly),
                    "directMessagesEnabled": .bool(directMessages),
                    "enableSearch": .bool(searchEnabled),
                    "enablePlugins": .bool(pluginsEnabled),
                    "webRtcSimulcastEnabled": .bool(simulcastEnabled),
                    "showWelcomeDialog": .bool(welcomeEnabled)
                ])
                if removesLogo {
                    try await session.changeLogo(fileId: nil)
                } else if let selectedLogo,
                          let data = try await selectedLogo.loadTransferable(type: Data.self) {
                    let contentType = selectedLogo.supportedContentTypes.first ?? .jpeg
                    let fileName = "server-logo.\(contentType.preferredFilenameExtension ?? "jpg")"
                    let mimeType = contentType.preferredMIMEType ?? "image/jpeg"
                    let fileId = try await session.uploadAttachment(data: data, fileName: fileName, mimeType: mimeType)
                    try await session.changeLogo(fileId: fileId)
                }
                status = L10n.t("admin.saved")
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }
}

private struct StorageServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var result: StorageSettingsResult?
    @State private var uploadsEnabled = true
    @State private var dmSharingEnabled = true
    @State private var storageQuota = 0
    @State private var maxFileSize = 0
    @State private var maxFiles = 10
    @State private var maxAvatarSize = 0
    @State private var maxBannerSize = 0
    @State private var userQuota = 0
    @State private var overflowAction = "delete"
    @State private var signedUrlsEnabled = true
    @State private var signedUrlsTtlSeconds = 3_600
    @State private var imageOptimizationEnabled = true
    @State private var imageOptimizationQuality = 80
    @State private var status: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            if let metrics = result?.diskMetrics {
                Section(L10n.t("admin.diskUsage")) {
                    LabeledContent(L10n.t("admin.diskTotal"), value: ByteCountFormatter.string(fromByteCount: Int64(metrics.totalSpace), countStyle: .file))
                    LabeledContent(L10n.t("admin.diskUsed"), value: ByteCountFormatter.string(fromByteCount: Int64(metrics.sharkordUsedSpace), countStyle: .file))
                    LabeledContent(L10n.t("admin.diskFree"), value: ByteCountFormatter.string(fromByteCount: Int64(metrics.freeSpace), countStyle: .file))
                }
            }

            if let result, !result.pluginStorage.isEmpty {
                Section(L10n.t("admin.pluginStorage")) {
                    ForEach(result.pluginStorage, id: \.pluginId) { usage in
                        LabeledContent(usage.pluginId) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(usage.usedSpace), countStyle: .file))
                        }
                        Text(L10n.format("admin.pluginStorageFiles", usage.fileCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.t("admin.storage")) {
                Toggle(L10n.t("admin.uploadsEnabled"), isOn: $uploadsEnabled)
                Toggle(L10n.t("admin.dmFileSharing"), isOn: $dmSharingEnabled)
                TextField(L10n.t("admin.totalQuotaBytes"), value: $storageQuota, format: .number)
                    .keyboardType(.numberPad)
                TextField(L10n.t("admin.maxFileSizeBytes"), value: $maxFileSize, format: .number)
                    .keyboardType(.numberPad)
                Stepper(L10n.format("admin.maxFiles", maxFiles), value: $maxFiles, in: 0...20)
                TextField(L10n.t("admin.maxAvatarSizeBytes"), value: $maxAvatarSize, format: .number)
                    .keyboardType(.numberPad)
                TextField(L10n.t("admin.maxBannerSizeBytes"), value: $maxBannerSize, format: .number)
                    .keyboardType(.numberPad)
                TextField(L10n.t("admin.perUserQuotaBytes"), value: $userQuota, format: .number)
                    .keyboardType(.numberPad)
                Picker(L10n.t("admin.overflowAction"), selection: $overflowAction) {
                    Text(L10n.t("admin.deleteOldFiles")).tag("delete")
                    Text(L10n.t("admin.preventUploads")).tag("prevent")
                }
                Toggle(L10n.t("admin.signedUrls"), isOn: $signedUrlsEnabled)
                TextField(L10n.t("admin.signedUrlsTtlSeconds"), value: $signedUrlsTtlSeconds, format: .number)
                    .keyboardType(.numberPad)
                    .disabled(!signedUrlsEnabled)
                Toggle(L10n.t("admin.imageOptimization"), isOn: $imageOptimizationEnabled)
                TextField(L10n.t("admin.imageOptimizationQuality"), value: $imageOptimizationQuality, format: .number)
                    .keyboardType(.numberPad)
                    .disabled(!imageOptimizationEnabled || !uploadsEnabled)
            }

            if let status {
                AdminStatusText(text: status)
            }
        }
        .navigationTitle(L10n.t("admin.storage"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("common.save"), action: save)
                    .disabled(isSaving)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let value = try await session.getStorageSettings()
            result = value
            uploadsEnabled = value.storageSettings.storageUploadEnabled ?? true
            dmSharingEnabled = value.storageSettings.storageFileSharingInDirectMessages ?? true
            storageQuota = value.storageSettings.storageQuota ?? 0
            maxFileSize = value.storageSettings.storageUploadMaxFileSize ?? 0
            maxFiles = value.storageSettings.storageMaxFilesPerMessage ?? 10
            maxAvatarSize = value.storageSettings.storageMaxAvatarSize ?? 0
            maxBannerSize = value.storageSettings.storageMaxBannerSize ?? 0
            userQuota = value.storageSettings.storageSpaceQuotaByUser ?? 0
            overflowAction = value.storageSettings.storageOverflowAction ?? "delete"
            signedUrlsEnabled = value.storageSettings.storageSignedUrlsEnabled ?? true
            signedUrlsTtlSeconds = value.storageSettings.storageSignedUrlsTtlSeconds ?? 3_600
            imageOptimizationEnabled = value.storageSettings.storageImageOptimizationEnabled ?? true
            imageOptimizationQuality = value.storageSettings.storageImageOptimizationQuality ?? 80
        } catch {
            status = SharkordSession.describe(error)
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await session.updateSettings([
                    "storageUploadEnabled": .bool(uploadsEnabled),
                    "storageFileSharingInDirectMessages": .bool(dmSharingEnabled),
                    "storageQuota": .int(storageQuota),
                    "storageUploadMaxFileSize": .int(maxFileSize),
                    "storageMaxAvatarSize": .int(maxAvatarSize),
                    "storageMaxBannerSize": .int(maxBannerSize),
                    "storageMaxFilesPerMessage": .int(maxFiles),
                    "storageSpaceQuotaByUser": .int(userQuota),
                    "storageOverflowAction": .string(overflowAction),
                    "storageSignedUrlsEnabled": .bool(signedUrlsEnabled),
                    "storageSignedUrlsTtlSeconds": .int(signedUrlsTtlSeconds),
                    "storageImageOptimizationEnabled": .bool(imageOptimizationEnabled),
                    "storageImageOptimizationQuality": .int(imageOptimizationQuality)
                ])
                status = L10n.t("admin.saved")
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }
}

private struct InvitesServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var invites: [SharkordInvite] = []
    @State private var maxUses = 0
    @State private var expiresInDays = 7
    @State private var selectedRoleId = 0
    @State private var inviteToDelete: SharkordInvite?
    @State private var status: String?
    @State private var isCreating = false

    var body: some View {
        List {
            Section(L10n.t("admin.createInvite")) {
                Stepper(L10n.format("admin.maxUses", maxUses == 0 ? L10n.t("admin.unlimited") : String(maxUses)), value: $maxUses, in: 0...100)
                Stepper(L10n.format("admin.expiresInDays", expiresInDays == 0 ? L10n.t("admin.never") : String(expiresInDays)), value: $expiresInDays, in: 0...365)
                Picker(L10n.t("admin.inviteRole"), selection: $selectedRoleId) {
                    Text(L10n.t("admin.defaultRole")).tag(0)
                    ForEach(session.roles) { role in
                        Text(role.name).tag(role.id)
                    }
                }
                Button {
                    createInvite()
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Label(L10n.t("admin.createInvite"), systemImage: "plus")
                    }
                }
                .disabled(isCreating)
            }

            Section(L10n.t("admin.invites")) {
                if invites.isEmpty {
                    Text(L10n.t("admin.noInvites"))
                        .foregroundStyle(.secondary)
                }
                ForEach(invites) { invite in
                    inviteRow(invite)
                }
            }

            if let status {
                Section { AdminStatusText(text: status) }
            }
        }
        .navigationTitle(L10n.t("admin.invites"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            L10n.t("admin.deleteInviteTitle"),
            isPresented: Binding(get: { inviteToDelete != nil }, set: { if !$0 { inviteToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteInvite() }
            Button(L10n.t("common.cancel"), role: .cancel) { inviteToDelete = nil }
        }
        .task { await load() }
    }

    private func inviteRow(_ invite: SharkordInvite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(invite.code)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Spacer()
                Text(L10n.format("admin.inviteUses", invite.uses, invite.maxUses.map(String.init) ?? L10n.t("admin.unlimited")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let url = session.inviteURL(code: invite.code).flatMap(URL.init(string:)) {
                    ShareLink(item: url) {
                        Label(L10n.t("admin.shareInvite"), systemImage: "square.and.arrow.up")
                    }
                }
                Spacer()
                Button(role: .destructive) { inviteToDelete = invite } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L10n.t("common.delete"))
            }
        }
        .padding(.vertical, 3)
    }

    private func load() async {
        do { invites = try await session.getAllInvites() }
        catch { status = SharkordSession.describe(error) }
    }

    private func createInvite() {
        Task {
            isCreating = true
            defer { isCreating = false }
            do {
                let expiry = expiresInDays == 0 ? nil : Int(Date().timeIntervalSince1970 * 1000) + expiresInDays * 86_400_000
                _ = try await session.createInvite(InviteCreate(
                    maxUses: maxUses == 0 ? nil : maxUses,
                    expiresAt: expiry,
                    roleId: selectedRoleId == 0 ? nil : selectedRoleId
                ))
                invites = try await session.getAllInvites()
                status = L10n.t("admin.inviteCreated")
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }

    private func deleteInvite() {
        guard let invite = inviteToDelete else { return }
        inviteToDelete = nil
        Task {
            do {
                try await session.deleteInvite(inviteId: invite.id)
                invites = try await session.getAllInvites()
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }
}

private struct UsersServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var users: [SharkordAdminUser] = []
    @State private var query = ""
    @State private var selectedUser: SharkordAdminUser?
    @State private var showsActions = false
    @State private var status: String?

    private var filteredUsers: [SharkordAdminUser] {
        guard !query.isEmpty else { return users }
        return users.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.identity ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filteredUsers) { user in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name).font(.body.weight(.semibold))
                        if let identity = user.identity {
                            Text(identity).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if user.banned {
                        Text(L10n.t("admin.banned"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    if user.id != session.ownUserId {
                        Menu {
                            if user.banned {
                                Button(L10n.t("admin.unban")) { moderate(user, action: .unban) }
                            } else {
                                Button(L10n.t("admin.kick"), role: .destructive) { moderate(user, action: .kick) }
                                Button(L10n.t("admin.ban"), role: .destructive) { moderate(user, action: .ban) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.t("admin.memberActions"))
                    }
                }
            }

            if filteredUsers.isEmpty {
                Text(L10n.t("admin.noMembers"))
                    .foregroundStyle(.secondary)
            }
            if let status {
                AdminStatusText(text: status)
            }
        }
        .searchable(text: $query)
        .navigationTitle(L10n.t("admin.users"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { users = try await session.getAllUsers() }
        catch { status = SharkordSession.describe(error) }
    }

    private enum ModerationAction { case kick, ban, unban }

    private func moderate(_ user: SharkordAdminUser, action: ModerationAction) {
        Task {
            do {
                switch action {
                case .kick: try await session.kickUser(userId: user.id, reason: nil)
                case .ban: try await session.banUser(userId: user.id, reason: nil)
                case .unban: try await session.unbanUser(userId: user.id)
                }
                users = try await session.getAllUsers()
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }
}

private struct RolesServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var roles: [SharkordRole] = []
    @State private var selectedRole: SharkordRole?
    @State private var status: String?

    var body: some View {
        List {
            ForEach(roles) { role in
                NavigationLink {
                    RoleServerAdminEditor(role: role)
                } label: {
                    HStack {
                        Circle().fill(adminColor(hex: role.color)).frame(width: 12, height: 12)
                        Text(role.name)
                        Spacer()
                        if role.isDefault {
                            Text(L10n.t("admin.defaultRole"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if role.id != 1 && !role.isPersistent {
                        Button(role: .destructive) { delete(role) } label: {
                            Label(L10n.t("common.delete"), systemImage: "trash")
                        }
                    }
                    if !role.isDefault {
                        Button { setDefault(role) } label: {
                            Label(L10n.t("admin.makeDefault"), systemImage: "checkmark.circle")
                        }
                        .tint(SharkordTheme.accent)
                    }
                }
            }
            if let status {
                AdminStatusText(text: status)
            }
        }
        .navigationTitle(L10n.t("admin.roles"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addRole() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.t("admin.addRole"))
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { roles = try await session.getAllRoles() }
        catch { status = SharkordSession.describe(error) }
    }

    private func addRole() {
        Task {
            do {
                _ = try await session.addRole()
                roles = try await session.getAllRoles()
            } catch {
                status = SharkordSession.describe(error)
            }
        }
    }

    private func setDefault(_ role: SharkordRole) {
        Task {
            do {
                try await session.setDefaultRole(roleId: role.id)
                roles = try await session.getAllRoles()
            } catch { status = SharkordSession.describe(error) }
        }
    }

    private func delete(_ role: SharkordRole) {
        Task {
            do {
                try await session.deleteRole(roleId: role.id)
                roles = try await session.getAllRoles()
            } catch { status = SharkordSession.describe(error) }
        }
    }
}

private struct RoleServerAdminEditor: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss
    let role: SharkordRole
    @State private var name: String
    @State private var color: String
    @State private var permissions: Set<String>
    @State private var quotaOverrideEnabled: Bool
    @State private var quota: Int
    @State private var status: String?
    @State private var isSaving = false

    init(role: SharkordRole) {
        self.role = role
        _name = State(initialValue: role.name)
        _color = State(initialValue: role.color)
        _permissions = State(initialValue: Set(role.permissions ?? []))
        _quotaOverrideEnabled = State(initialValue: role.storageQuotaOverrideEnabled ?? false)
        _quota = State(initialValue: role.storageSpaceQuota ?? 0)
    }

    var body: some View {
        Form {
            Section(L10n.t("admin.roleDetails")) {
                TextField(L10n.t("admin.name"), text: $name)
                TextField(L10n.t("admin.color"), text: $color)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle(L10n.t("admin.storageQuotaOverride"), isOn: $quotaOverrideEnabled)
                if quotaOverrideEnabled {
                    TextField(L10n.t("admin.perUserQuotaBytes"), value: $quota, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            Section(L10n.t("admin.permissions")) {
                ForEach(Permission.allCases, id: \.rawValue) { permission in
                    Toggle(L10n.t("permission.\(permission.rawValue)"), isOn: permissionBinding(permission))
                }
            }
            if let status {
                AdminStatusText(text: status)
            }
        }
        .navigationTitle(role.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("common.save"), action: save)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func permissionBinding(_ permission: Permission) -> Binding<Bool> {
        Binding(
            get: { permissions.contains(permission.rawValue) },
            set: { enabled in
                if enabled { permissions.insert(permission.rawValue) }
                else { permissions.remove(permission.rawValue) }
            }
        )
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await session.updateRole(RoleUpdate(
                    roleId: role.id,
                    name: name,
                    color: color,
                    permissions: permissions.sorted(),
                    storageQuotaOverrideEnabled: quotaOverrideEnabled,
                    storageSpaceQuota: quota
                ))
                dismiss()
            } catch { status = SharkordSession.describe(error) }
        }
    }
}

private struct EmojisServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var emojis: [SharkordEmoji] = []
    @State private var name = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var emojiToRename: SharkordEmoji?
    @State private var renamedName = ""
    @State private var emojiToDelete: SharkordEmoji?
    @State private var status: String?
    @State private var isAdding = false

    var body: some View {
        List {
            Section(L10n.t("admin.addEmoji")) {
                TextField(L10n.t("admin.emojiName"), text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(L10n.t("admin.chooseEmojiImage"), systemImage: "photo")
                }
                Button {
                    addEmoji()
                } label: {
                    if isAdding { ProgressView() }
                    else { Label(L10n.t("admin.addEmoji"), systemImage: "plus") }
                }
                .disabled(isAdding || selectedPhoto == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section(L10n.t("admin.emojis")) {
                ForEach(emojis) { emoji in
                    HStack(spacing: 12) {
                        if let file = emoji.file, let url = session.publicFileURL(for: file) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 32, height: 32)
                        }
                        Text(":\(emoji.name):")
                        Spacer()
                        Button { emojiToRename = emoji; renamedName = emoji.name } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(L10n.t("admin.rename"))
                        Button(role: .destructive) { emojiToDelete = emoji } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L10n.t("common.delete"))
                    }
                }
                if emojis.isEmpty {
                    Text(L10n.t("admin.noEmojis"))
                        .foregroundStyle(.secondary)
                }
            }
            if let status { AdminStatusText(text: status) }
        }
        .navigationTitle(L10n.t("admin.emojis"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.t("admin.renameEmoji"), isPresented: Binding(get: { emojiToRename != nil }, set: { if !$0 { emojiToRename = nil } })) {
            TextField(L10n.t("admin.emojiName"), text: $renamedName)
            Button(L10n.t("common.save")) { renameEmoji() }
            Button(L10n.t("common.cancel"), role: .cancel) { emojiToRename = nil }
        }
        .confirmationDialog(
            L10n.t("admin.deleteEmojiTitle"),
            isPresented: Binding(get: { emojiToDelete != nil }, set: { if !$0 { emojiToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteEmoji() }
            Button(L10n.t("common.cancel"), role: .cancel) { emojiToDelete = nil }
        }
        .task { await load() }
    }

    private func load() async {
        do { emojis = try await session.getAllEmojis() }
        catch { status = SharkordSession.describe(error) }
    }

    private func addEmoji() {
        guard let selectedPhoto else { return }
        Task {
            isAdding = true
            defer { isAdding = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let pngData = image.pngData()
                else {
                    throw TRPCClientError(code: "BAD_REQUEST", message: L10n.t("admin.invalidEmojiImage"))
                }
                let temporaryId = try await session.uploadAttachment(data: pngData, fileName: name + ".png", mimeType: "image/png")
                try await session.addEmojis([EmojiCreateEntry(fileId: temporaryId, name: name)])
                emojis = try await session.getAllEmojis()
                name = ""
                self.selectedPhoto = nil
                status = L10n.t("admin.emojiAdded")
            } catch { status = SharkordSession.describe(error) }
        }
    }

    private func renameEmoji() {
        guard let emoji = emojiToRename else { return }
        emojiToRename = nil
        Task {
            do {
                try await session.updateEmoji(emojiId: emoji.id, name: renamedName)
                emojis = try await session.getAllEmojis()
            } catch { status = SharkordSession.describe(error) }
        }
    }

    private func deleteEmoji() {
        guard let emoji = emojiToDelete else { return }
        emojiToDelete = nil
        Task {
            do {
                try await session.deleteEmoji(emojiId: emoji.id)
                emojis = try await session.getAllEmojis()
            } catch { status = SharkordSession.describe(error) }
        }
    }
}

private struct PluginsServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var plugins: [PluginInfo] = []
    @State private var selectedTab = "installed"
    @State private var marketplaceSearch = ""
    @State private var marketplaceEntries: [MobileMarketplacePluginEntry] = []
    @State private var marketplaceError: String?
    @State private var isMarketplaceLoading = false
    @State private var hasLoadedMarketplace = false
    @State private var pendingMarketplaceAction: MobilePendingPluginAction?
    @State private var pluginToRemove: PluginInfo?
    @State private var isPerformingAction = false
    @State private var status: String?

    private var filteredMarketplaceEntries: [MobileMarketplacePluginEntry] {
        let query = marketplaceSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return marketplaceEntries }
        return marketplaceEntries.filter { entry in
            entry.plugin.name.localizedCaseInsensitiveContains(query)
                || entry.plugin.description.localizedCaseInsensitiveContains(query)
                || entry.plugin.author.localizedCaseInsensitiveContains(query)
                || (entry.plugin.tags?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
                || (entry.plugin.categories?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    var body: some View {
        List {
            Picker(L10n.t("admin.plugins"), selection: $selectedTab) {
                Text(L10n.t("admin.installedPlugins")).tag("installed")
                Text(L10n.t("admin.marketplace")).tag("marketplace")
            }
            .pickerStyle(.segmented)

            if selectedTab == "installed" {
                Section {
                    Text(L10n.t("admin.pluginUiLimit"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(plugins) { plugin in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(
                            get: { plugin.enabled },
                            set: { setEnabled($0, for: plugin) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plugin.name ?? plugin.pluginId)
                                    .font(.body.weight(.semibold))
                                Text(plugin.pluginId)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let description = plugin.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let loadError = plugin.loadError {
                            Text(loadError).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { pluginToRemove = plugin } label: {
                            Label(L10n.t("admin.remove"), systemImage: "trash")
                        }
                    }
                }
                if plugins.isEmpty {
                    Text(L10n.t("admin.noPlugins"))
                        .foregroundStyle(.secondary)
                }
            } else {
                TextField(L10n.t("admin.marketplaceSearch"), text: $marketplaceSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isMarketplaceLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let marketplaceError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(marketplaceError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(L10n.t("admin.marketplaceRetry")) {
                            Task { await loadMarketplace() }
                        }
                    }
                } else if filteredMarketplaceEntries.isEmpty {
                    Text(L10n.t("admin.marketplaceNoResults"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredMarketplaceEntries) { entry in
                        let installed = plugins.first { $0.pluginId == entry.plugin.id }
                        MobileMarketplacePluginRow(entry: entry, installedVersion: installed?.version) { version, isUpdate in
                            pendingMarketplaceAction = MobilePendingPluginAction(
                                pluginId: entry.plugin.id,
                                pluginName: entry.plugin.name,
                                version: version,
                                isUpdate: isUpdate
                            )
                        }
                    }
                }
            }
            if let status { AdminStatusText(text: status) }
        }
        .navigationTitle(L10n.t("admin.plugins"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if selectedTab == "marketplace" {
                        Task { await loadMarketplace() }
                    } else {
                        Task { await load() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L10n.t("admin.refreshPlugins"))
                .disabled(isMarketplaceLoading || isPerformingAction)
            }
        }
        .task { await load() }
        .onChange(of: selectedTab) { _, tab in
            if tab == "marketplace", !hasLoadedMarketplace {
                Task { await loadMarketplace() }
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingMarketplaceAction != nil || pluginToRemove != nil },
                set: { if !$0 { pendingMarketplaceAction = nil; pluginToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingMarketplaceAction {
                Button(L10n.t(action.isUpdate ? "admin.updatePlugin" : "admin.installPlugin")) {
                    Task { await performMarketplaceAction(action) }
                }
                .disabled(isPerformingAction)
            }
            if let plugin = pluginToRemove {
                Button(L10n.t("admin.remove"), role: .destructive) {
                    Task { await remove(plugin) }
                }
                .disabled(isPerformingAction)
            }
            Button(L10n.t("common.cancel"), role: .cancel) {
                pendingMarketplaceAction = nil
                pluginToRemove = nil
            }
        } message: {
            Text(pendingMarketplaceAction == nil ? L10n.t("admin.removePluginConfirm") : L10n.t("admin.pluginInstallWarning"))
        }
    }

    private var confirmationTitle: String {
        if let action = pendingMarketplaceAction {
            return L10n.format("admin.pluginActionTitle", action.pluginName, action.version)
        }
        return L10n.t("admin.removePluginTitle")
    }

    private func load() async {
        do { plugins = try await session.getPlugins() }
        catch { status = SharkordSession.describe(error) }
    }

    private func loadMarketplace() async {
        isMarketplaceLoading = true
        marketplaceError = nil
        do {
            marketplaceEntries = try await MobilePluginMarketplaceCatalog.fetch()
            hasLoadedMarketplace = true
        } catch {
            marketplaceError = L10n.t("admin.marketplaceFetchFailed")
        }
        isMarketplaceLoading = false
    }

    private func setEnabled(_ enabled: Bool, for plugin: PluginInfo) {
        Task {
            do {
                try await session.togglePlugin(pluginId: plugin.pluginId, enabled: enabled)
                await load()
            } catch { status = SharkordSession.describe(error) }
        }
    }

    private func remove(_ plugin: PluginInfo) async {
        pluginToRemove = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await session.removePlugin(pluginId: plugin.pluginId)
            await load()
        } catch { status = SharkordSession.describe(error) }
    }

    private func performMarketplaceAction(_ action: MobilePendingPluginAction) async {
        pendingMarketplaceAction = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            if action.isUpdate {
                try await session.updatePlugin(pluginId: action.pluginId, version: action.version)
            } else {
                try await session.installPlugin(pluginId: action.pluginId, version: action.version)
            }
            plugins = try await session.getPlugins()
            status = L10n.format(action.isUpdate ? "admin.pluginUpdateComplete" : "admin.pluginInstallComplete", action.pluginName)
        } catch {
            status = SharkordSession.describe(error)
        }
    }
}

private struct MobilePendingPluginAction {
    let pluginId: String
    let pluginName: String
    let version: String
    let isUpdate: Bool
}

private struct MobileMarketplacePluginRow: View {
    let entry: MobileMarketplacePluginEntry
    let installedVersion: String?
    let onAction: (String, Bool) -> Void

    private var compatibleVersion: MobileMarketplacePluginVersion? {
        MobilePluginMarketplaceCatalog.compatibleVersion(in: entry)
    }

    private var canUpdate: Bool {
        guard let compatibleVersion, let installedVersion else { return false }
        return MobileMarketplaceVersionOrder.isNewer(compatibleVersion.version, than: installedVersion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let logo = URL(string: entry.plugin.logo) {
                    AsyncImage(url: logo) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.plugin.name)
                        .font(.body.weight(.semibold))
                    Text(L10n.format("admin.pluginBy", entry.plugin.author))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.plugin.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(SharkordTheme.accentSoft)
                        .accessibilityLabel(L10n.t("admin.verifiedPlugin"))
                }
            }

            Text(entry.plugin.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let compatibleVersion {
                HStack {
                    Text(L10n.format("admin.pluginVersion", compatibleVersion.version))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if installedVersion == nil {
                        Button(L10n.t("admin.installPlugin")) {
                            onAction(compatibleVersion.version, false)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SharkordTheme.accent)
                    } else if canUpdate {
                        Button(L10n.t("admin.updatePlugin")) {
                            onAction(compatibleVersion.version, true)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Label(L10n.t("admin.installed"), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(SharkordTheme.success)
                    }
                }
            } else {
                Text(L10n.t("admin.pluginIncompatible"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let homepage = entry.plugin.homepage, let url = URL(string: homepage) {
                Link(L10n.t("admin.pluginHomepage"), destination: url)
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct UpdatesServerAdminView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var update: UpdateInfo?
    @State private var status: String?
    @State private var isUpdating = false

    var body: some View {
        Form {
            if let update {
                LabeledContent(L10n.t("admin.currentVersion"), value: update.currentVersion)
                LabeledContent(L10n.t("admin.latestVersion"), value: update.latestVersion)
                Text(L10n.t(update.hasUpdate ? "admin.updateAvailable" : "admin.noUpdateAvailable"))
                    .foregroundStyle(update.hasUpdate ? .orange : SharkordTheme.success)
                if update.hasUpdate {
                    Button {
                        startUpdate()
                    } label: {
                        if isUpdating { ProgressView() }
                        else { Label(L10n.t("admin.updateServer"), systemImage: "arrow.down.circle") }
                    }
                    .disabled(isUpdating)
                }
            }
            if let status { AdminStatusText(text: status) }
        }
        .navigationTitle(L10n.t("admin.updates"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(L10n.t("admin.checkUpdates"))
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { update = try await session.getUpdate() }
        catch { status = SharkordSession.describe(error) }
    }

    private func startUpdate() {
        Task {
            isUpdating = true
            defer { isUpdating = false }
            do {
                try await session.updateServer()
                status = L10n.t("admin.updateStarted")
            } catch { status = SharkordSession.describe(error) }
        }
    }
}

private struct AdminStatusText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(SharkordTheme.accentSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func adminColor(hex: String) -> Color {
    let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x262626
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}
