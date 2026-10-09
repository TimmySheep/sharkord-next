import SharkordCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// settings for language, connection and developer-only tools.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileCard
                languageCard
                notificationsCard
                if canManageAnyServerFeatures {
                    serverManagementCard
                }
                connectionCard
                watchAccountLink
                developerCard

                SharkordSecondaryButton(
                    title: L10n.t("settings.disconnect"),
                    symbol: "rectangle.portrait.and.arrow.right",
                    tint: SharkordTheme.danger,
                    background: SharkordTheme.dangerDeep
                ) {
                    model.disconnect()
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(L10n.t("nav.settings"))
        .navigationBarTitleDisplayMode(.large)
    }

    private var profileCard: some View {
        ProfileSettingsCard()
            .environmentObject(session)
    }

    private var canManageAnyServerFeatures: Bool {
        [
            Permission.manageChannels,
            .manageCategories,
            Permission.manageSettings,
            .manageStorage,
            .manageUsers,
            .manageRoles,
            .manageEmojis,
            .manageInvites,
            .managePlugins,
            .manageUpdates
        ].contains(where: session.hasPermission)
    }

    private var serverManagementCard: some View {
        NavigationLink {
            ServerManagementView()
        } label: {
            HStack {
                Label(L10n.t("admin.title"), systemImage: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(SharkordTheme.textPrimary)
            .padding(18)
            .sharkordCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(icon: "globe", text: L10n.t("settings.language"), tint: SharkordTheme.accentSoft)

            Menu {
                ForEach(L10n.supportedLanguages, id: \.code) { language in
                    Button {
                        model.setLanguage(language.code)
                    } label: {
                        if model.language == language.code {
                            Label(language.nativeName, systemImage: "checkmark")
                        } else {
                            Text(language.nativeName)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentLanguageName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SharkordTheme.accentSoft)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

        }
        .sharkordCard(cornerRadius: 24)
    }

    private var currentLanguageName: String {
        L10n.supportedLanguages.first { $0.code == model.language }?.nativeName
            ?? L10n.supportedLanguages[0].nativeName
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(icon: "bell.badge", text: L10n.t("settings.notifications"), tint: SharkordTheme.accentSoft)

            Toggle(
                L10n.t("settings.notificationsEnabled"),
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { model.setNotificationsEnabled($0) }
                )
            )

            Toggle(
                L10n.t("settings.mentionsOnly"),
                isOn: Binding(
                    get: { model.notificationsForMentions },
                    set: { model.setNotificationOption(.mentions, enabled: $0) }
                )
            )

            Toggle(
                L10n.t("settings.directMessageNotifications"),
                isOn: Binding(
                    get: { model.notificationsForDms },
                    set: { model.setNotificationOption(.directMessages, enabled: $0) }
                )
            )

            Toggle(
                L10n.t("settings.replyNotifications"),
                isOn: Binding(
                    get: { model.notificationsForReplies },
                    set: { model.setNotificationOption(.replies, enabled: $0) }
                )
            )

            Toggle(L10n.t("settings.soundEffects"), isOn: $model.soundEffectsEnabled)

            if let notificationStatus = model.notificationStatus {
                Text(notificationStatus)
                    .font(.caption)
                    .foregroundStyle(SharkordTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L10n.t("settings.notificationHint"))
                .font(.caption)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(SharkordTheme.accentSoft)
        .sharkordCard(cornerRadius: 24)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(
                icon: "network",
                text: L10n.t("settings.connection"),
                tint: SharkordTheme.accentSoft
            )

            infoRow(label: L10n.t("settings.server"), value: model.serverDisplayName)

            if let user = session.ownUser {
                infoRow(label: L10n.t("settings.account"), value: user.name)
            }
        }
        .sharkordCard(cornerRadius: 24)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(SharkordTheme.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var developerCard: some View {
        NavigationLink {
            DeveloperSettingsView()
        } label: {
            HStack {
                Label(L10n.t("settings.developer"), systemImage: "wrench.and.screwdriver")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(SharkordTheme.textPrimary)
            .padding(18)
            .sharkordCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    private var watchAccountLink: some View {
        NavigationLink {
            WatchAccountSettingsView()
        } label: {
            HStack {
                Label(L10n.t("watchAccount.title"), systemImage: "applewatch")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(SharkordTheme.textPrimary)
            .padding(18)
            .sharkordCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSettingsCard: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var name = ""
    @State private var bio = ""
    @State private var profileColorHex = "#262626"
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var selectedAvatarImage: UIImage?
    @State private var selectedBanner: PhotosPickerItem?
    @State private var removesAvatar = false
    @State private var removesBanner = false
    @State private var isSaving = false
    @State private var status: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(icon: "person.crop.circle", text: L10n.t("settings.profile"), tint: SharkordTheme.accentSoft)

            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedAvatar, matching: .images) {
                        Label(L10n.t("settings.changeAvatar"), systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    if session.ownUser?.avatar != nil {
                        Button(L10n.t(removesAvatar ? "settings.keepAvatar" : "settings.removeAvatar")) {
                            removesAvatar.toggle()
                            if removesAvatar { selectedAvatar = nil }
                        }
                        .font(.caption)
                        .foregroundStyle(SharkordTheme.danger)
                    }
                }
                .disabled(isSaving || session.phase != .connected)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("settings.banner"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
                banner
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    PhotosPicker(selection: $selectedBanner, matching: .images) {
                        Label(L10n.t("settings.changeBanner"), systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    if session.ownUser?.banner != nil {
                        Button(L10n.t(removesBanner ? "settings.keepBanner" : "settings.removeBanner")) {
                            removesBanner.toggle()
                            if removesBanner { selectedBanner = nil }
                        }
                        .font(.caption)
                        .foregroundStyle(SharkordTheme.danger)
                    }
                }
            }
            .disabled(isSaving || session.phase != .connected)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("settings.profileColor"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
                ColorPicker("", selection: profileColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .tint(SharkordTheme.accent)
            }
            .disabled(isSaving || session.phase != .connected)

            TextField(L10n.t("settings.displayName"), text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.nickname)
                .padding(16)
                .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isSaving || session.phase != .connected)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("settings.bio"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
                TextField(L10n.t("settings.bioPlaceholder"), text: $bio, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(16)
                    .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(isSaving || session.phase != .connected)
                Text("\(bio.count)/160")
                    .font(.caption2)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            SharkordPrimaryButton(
                title: isSaving ? L10n.t("settings.profileSaving") : L10n.t("settings.saveProfile"),
                symbol: "checkmark",
                enabled: canSaveProfile
            ) {
                Task {
                    await saveProfile()
                }
            }

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? SharkordTheme.danger : SharkordTheme.accentSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sharkordCard(cornerRadius: 24)
        .onAppear(perform: loadProfile)
        .onChange(of: session.ownUser?.name) { _, _ in refreshProfileIfIdle() }
        .onChange(of: session.ownUser?.bio) { _, _ in refreshProfileIfIdle() }
        .onChange(of: session.ownUser?.profileColor) { _, _ in refreshProfileIfIdle() }
        .onChange(of: selectedAvatar) { _, photo in
            guard let photo else {
                selectedAvatarImage = nil
                return
            }
            removesAvatar = false
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      selectedAvatar == photo
                else {
                    return
                }
                selectedAvatarImage = UIImage(data: data)
            }
        }
        .onChange(of: selectedBanner) { _, photo in
            if photo != nil { removesBanner = false }
        }
    }

    private var avatar: some View {
        Group {
            if let selectedAvatarImage {
                Image(uiImage: selectedAvatarImage)
                    .resizable()
                    .scaledToFill()
            } else if let file = session.ownUser?.avatar,
                      let url = session.publicFileURL(for: file),
                      !removesAvatar {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .accessibilityLabel(L10n.t("settings.avatar"))
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(SharkordTheme.field)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }
    }

    private var banner: some View {
        Group {
            if let file = session.ownUser?.banner, let url = session.publicFileURL(for: file), !removesBanner {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    bannerPlaceholder
                }
            } else {
                bannerPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bannerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(SharkordTheme.field)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }
    }

    private var profileColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: profileColorHex) },
            set: { profileColorHex = $0.hexString }
        )
    }

    private var canSaveProfile: Bool {
        guard let user = session.ownUser else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.phase == .connected
            && !isSaving
            && !trimmedName.isEmpty
            && bio.count <= 160
            && (trimmedName != user.name
                || bio != (user.bio ?? "")
                || profileColorHex != user.profileColor
                || selectedAvatar != nil
                || selectedBanner != nil
                || removesAvatar
                || removesBanner)
    }

    @MainActor
    private func loadProfile() {
        guard let user = session.ownUser else { return }
        name = user.name
        bio = user.bio ?? ""
        profileColorHex = user.profileColor
    }

    @MainActor
    private func refreshProfileIfIdle() {
        if !isSaving { loadProfile() }
    }

    @MainActor
    private func saveProfile() async {
        guard session.ownUser != nil else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, bio.count <= 160 else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.updateProfile(
                name: trimmedName,
                profileColor: profileColorHex,
                bio: bio.isEmpty ? nil : bio
            )
            if removesAvatar {
                try await session.changeAvatar(fileId: nil)
                removesAvatar = false
            } else if let selectedAvatar {
                let fileId = try await upload(selectedAvatar, baseName: "avatar")
                try await session.changeAvatar(fileId: fileId)
                self.selectedAvatar = nil
            }
            if removesBanner {
                try await session.changeBanner(fileId: nil)
                removesBanner = false
            } else if let selectedBanner {
                let fileId = try await upload(selectedBanner, baseName: "banner")
                try await session.changeBanner(fileId: fileId)
                self.selectedBanner = nil
            }
            status = L10n.t("settings.profileSaved")
            statusIsError = false
            loadProfile()
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }

    @MainActor
    private func upload(_ photo: PhotosPickerItem, baseName: String) async throws -> String {
        guard let data = try await photo.loadTransferable(type: Data.self) else {
            throw ProfileSettingsError.unreadableImage
        }
        let contentType = photo.supportedContentTypes.first ?? .jpeg
        let fileName = "\(baseName).\(contentType.preferredFilenameExtension ?? "jpg")"
        let mimeType = contentType.preferredMIMEType ?? "image/jpeg"
        return try await session.uploadAttachment(data: data, fileName: fileName, mimeType: mimeType)
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x262626
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    var hexString: String {
        let color = UIColor(self)
        var redComponent: CGFloat = 0.15
        var greenComponent: CGFloat = 0.15
        var blueComponent: CGFloat = 0.15
        color.getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: nil)
        let red = Int((redComponent * 255).rounded())
        let green = Int((greenComponent * 255).rounded())
        let blue = Int((blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private enum ProfileSettingsError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        L10n.t("settings.avatarReadFailed")
    }
}

private struct WatchAccountSettingsView: View {
    @EnvironmentObject private var manager: WatchAccountManager
    @EnvironmentObject private var session: SharkordSession
    @State private var identity = ""
    @State private var invite = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeading(icon: "applewatch", text: L10n.t("watchAccount.title"), tint: SharkordTheme.accentSoft)
                    Text(L10n.t("watchAccount.description"))
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pairingStatus)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(manager.isPaired && manager.isWatchAppInstalled ? SharkordTheme.accentSoft : SharkordTheme.textSecondary)
                }
                .sharkordCard(cornerRadius: 24)

                VStack(alignment: .leading, spacing: 12) {
                    CardHeading(icon: "person.badge.key", text: L10n.t("watchAccount.account"), tint: SharkordTheme.accentSoft)
                    if let accountIdentity = manager.accountIdentity {
                        Text(L10n.format("watchAccount.currentAccount", accountIdentity))
                            .font(.footnote)
                            .foregroundStyle(SharkordTheme.textPrimary)
                        SharkordSecondaryButton(
                            title: L10n.t("watchAccount.syncAgain"),
                            symbol: "arrow.triangle.2.circlepath",
                            tint: SharkordTheme.accentSoft,
                            background: SharkordTheme.field
                        ) {
                            manager.syncSavedAccount()
                        }
                    } else {
                        Text(L10n.t("watchAccount.noAccount"))
                            .font(.footnote)
                            .foregroundStyle(SharkordTheme.textSecondary)
                    }

                    TextField(L10n.t("watchAccount.identity"), text: $identity)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .padding(16)
                        .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    SecureField(L10n.t("watchAccount.invite"), text: $invite)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(L10n.t("watchAccount.registrationHint"))
                        .font(.caption)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SharkordPrimaryButton(
                        title: manager.isWorking ? L10n.t("watchAccount.creating") : L10n.t("watchAccount.createAndSync"),
                        symbol: "arrow.up.forward",
                        enabled: manager.accountIdentity == nil && manager.isPaired && manager.isWatchAppInstalled && session.phase == .connected && !manager.isWorking
                    ) {
                        Task {
                            await manager.createAccount(identity: identity, invite: invite)
                        }
                    }

                    if let statusMessage = manager.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(SharkordTheme.accentSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .sharkordCard(cornerRadius: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(L10n.t("watchAccount.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if identity.isEmpty {
                identity = manager.accountIdentity ?? manager.suggestedIdentity
            }
        }
    }

    private var pairingStatus: String {
        guard manager.isPaired else {
            return L10n.t("watchAccount.notPaired")
        }
        guard manager.isWatchAppInstalled else {
            return L10n.t("watchAccount.appNotInstalled")
        }
        return L10n.t("watchAccount.ready")
    }
}

private struct DeveloperSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                diagnosticsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(L10n.t("settings.developer"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(icon: "doc.text.magnifyingglass", text: L10n.t("settings.diagnostics"), tint: SharkordTheme.accentSoft)

            NavigationLink {
                DiagnosticsLogView()
            } label: {
                HStack {
                    Label(L10n.t("settings.viewLogs"), systemImage: "doc.text")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(SharkordTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .sharkordCard(cornerRadius: 24)
    }
}

struct DiagnosticsLogView: View {
    @EnvironmentObject private var watchAccountManager: WatchAccountManager
    @State private var logText = ""
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var showExportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(logText.isEmpty ? L10n.t("settings.noLogs") : logText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let statusMessage = watchAccountManager.logsStatusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.textSecondary)
                }

                SharkordSecondaryButton(
                    title: watchAccountManager.isCollectingLogs
                        ? L10n.t("settings.collectingDeviceLogs")
                        : L10n.t("settings.collectDeviceLogs"),
                    symbol: "square.and.arrow.up",
                    tint: SharkordTheme.accentSoft,
                    background: SharkordTheme.field,
                    action: collectAndExport
                )
                .disabled(watchAccountManager.isCollectingLogs)
            }
            .padding(20)
        }
        .background(BrandBackground())
        .navigationTitle(L10n.t("settings.diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            logText = DiagnosticsLogger.shared.recentText()
        }
        .sheet(isPresented: $showShareSheet) {
            VStack(spacing: 18) {
                Text(L10n.t("settings.exportLogs"))
                    .font(.headline)
                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label(L10n.t("settings.shareLogs"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        .alert(L10n.t("settings.exportFailed"), isPresented: $showExportError) {
            Button(L10n.t("common.done"), role: .cancel) {}
        }
    }

    private func collectAndExport() {
        Task {
            let watchLogs = await watchAccountManager.collectWatchLogs()
            logText = DiagnosticsLogger.shared.recentText()
            do {
                exportedURL = try DiagnosticsLogger.shared.exportURL(additionalLogs: watchLogs)
                showShareSheet = true
            } catch {
                DiagnosticsLogger.shared.error("export", "diagnostic log export failed", error: error)
                showExportError = true
            }
        }
    }

}
