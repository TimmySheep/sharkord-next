import AppKit
import SharkordCore
import SwiftUI

/// Every settings surface the web client has, in one sheet: the viewer's own account
/// screens and the server administration screens, gated by the same permissions.
enum SettingsSection: String, Identifiable, CaseIterable {
    case profile
    case password
    case notifications
    case others
    case shortcuts
    case general
    case storage
    case users
    case roles
    case emojis
    case invites
    case plugins
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:
            return L10n.t("profileTab", ns: "settings")
        case .password:
            return L10n.t("passwordTab", ns: "settings")
        case .notifications:
            return L10n.t("notificationsTab", ns: "settings")
        case .others:
            return L10n.t("othersTab", ns: "settings")
        case .shortcuts:
            return L10n.t("keyboardShortcutsTab", ns: "macos")
        case .general:
            return L10n.t("generalTab", ns: "settings")
        case .storage:
            return L10n.t("storageTab", ns: "settings")
        case .users:
            return L10n.t("usersTab", ns: "settings")
        case .roles:
            return L10n.t("rolesTab", ns: "settings")
        case .emojis:
            return L10n.t("emojisTab", ns: "settings")
        case .invites:
            return L10n.t("invitesTab", ns: "settings")
        case .plugins:
            return L10n.t("pluginsTab", ns: "settings")
        case .updates:
            return L10n.t("updatesTab", ns: "settings")
        }
    }

    var systemImage: String {
        switch self {
        case .profile:
            return "person.crop.circle"
        case .password:
            return "key"
        case .notifications:
            return "bell"
        case .others:
            return "slider.horizontal.3"
        case .shortcuts:
            return "keyboard"
        case .general:
            return "gearshape"
        case .storage:
            return "internaldrive"
        case .users:
            return "person.2"
        case .roles:
            return "person.badge.key"
        case .emojis:
            return "face.smiling"
        case .invites:
            return "envelope"
        case .plugins:
            return "puzzlepiece"
        case .updates:
            return "arrow.triangle.2.circlepath"
        }
    }

    /// Server tabs appear only for viewers who can actually use them.
    var isServerSection: Bool {
        switch self {
        case .general, .storage, .users, .roles, .emojis, .invites, .plugins, .updates:
            return true
        case .profile, .password, .notifications, .others, .shortcuts:
            return false
        }
    }

    @MainActor
    static func visible(to session: SharkordSession) -> [SettingsSection] {
        allCases.filter { section in
            guard section.isServerSection else {
                return true
            }

            switch section {
            case .general:
                return session.canManageSettings
            case .storage:
                return session.canManageStorage
            case .users:
                return session.canManageUsers
            case .roles:
                return session.canManageRoles
            case .emojis:
                return session.canManageEmojis
            case .invites:
                return session.canManageInvites
            case .plugins:
                return session.canManagePlugins
            case .updates:
                return session.hasPermission(.manageUpdates)
            default:
                return false
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    let initialSection: SettingsSection

    @State private var section: SettingsSection = .profile

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.visible(to: session), selection: $section) { item in
                Label {
                    Text(item.title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: item.systemImage)
                }
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            section = SettingsSection.visible(to: session).contains(initialSection)
                ? initialSection
                : .profile
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .profile:
            ProfileSettingsView()
        case .password:
            PasswordSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .others:
            OtherSettingsView()
        case .shortcuts:
            KeyboardShortcutsSettingsView()
        case .general:
            GeneralServerSettingsView()
        case .storage:
            StorageSettingsView()
        case .users:
            UsersSettingsView()
        case .roles:
            RolesSettingsView()
        case .emojis:
            EmojisSettingsView()
        case .invites:
            InvitesSettingsView()
        case .plugins:
            PluginsSettingsView()
        case .updates:
            UpdatesSettingsView()
        }
    }
}

/// Shared chrome for a settings screen: title, scrollable body and a save bar.
struct SettingsSectionLayout<Body: View>: View {
    let title: String
    var subtitle: String?
    var onSave: (() -> Void)?
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)

            Divider()

            ScrollView {
                content()
                    .padding(18)
            }

            if let onSave {
                Divider()

                HStack {
                    Spacer()

                    Button(L10n.t("saveChanges", ns: "settings"), action: onSave)
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
        }
    }
}

/// Labeled form row used by every settings screen.
struct SettingsField<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))

            if let help {
                Text(help)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            control()
        }
        .padding(.bottom, 12)
    }
}

// MARK: - user settings

struct ProfileSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var name = ""
    @State private var bio = ""
    @State private var profileColor = "#1447E6"
    @State private var avatarFileId: String?
    @State private var bannerFileId: String?
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("profileTitle", ns: "settings"),
            subtitle: L10n.t("profileDesc", ns: "settings"),
            onSave: save
        ) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsField(label: L10n.t("avatarLabel", ns: "settings")) {
                    HStack(spacing: 10) {
                        AvatarView(user: session.ownUser, size: 54)

                        Button(L10n.t("removeImage", ns: "common")) {
                            avatarFileId = ""
                        }

                        Button(L10n.t("uploadEmojiBtn", ns: "settings")) {
                            pickImage { url in
                                Task {
                                    if let id = await upload(url: url) {
                                        avatarFileId = id
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsField(label: L10n.t("usernameLabel", ns: "settings")) {
                    TextField(L10n.t("usernamePlaceholder", ns: "settings"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                SettingsField(label: L10n.t("profileColorLabel", ns: "settings")) {
                    HStack(spacing: 8) {
                        TextField("#1447E6", text: $profileColor)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)

                        ColorPicker("", selection: Binding(
                            get: { Color(hex: profileColor) ?? Theme.accent },
                            set: { profileColor = $0.hexString }
                        ))
                        .labelsHidden()
                    }
                }

                SettingsField(label: L10n.t("bioLabel", ns: "settings")) {
                    TextEditor(text: $bio)
                        .frame(minHeight: 80, maxHeight: 120)
                        .textFieldStyle(.roundedBorder)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? .red : .green)
                }
            }
        }
        .onAppear {
            name = session.ownUser?.name ?? ""
            bio = session.ownUser?.bio ?? ""
            profileColor = session.ownUser?.profileColor ?? "#1447E6"
        }
    }

    private func save() {
        Task {
            do {
                try await session.updateProfile(
                    name: name,
                    profileColor: profileColor,
                    bio: bio.isEmpty ? nil : bio
                )

                if let avatarFileId {
                    try await session.changeAvatar(fileId: avatarFileId.isEmpty ? nil : avatarFileId)
                }

                if let bannerFileId {
                    try await session.changeBanner(fileId: bannerFileId.isEmpty ? nil : bannerFileId)
                }

                statusMessage = L10n.t("profileUpdated", ns: "settings")
                isError = false
            } catch {
                statusMessage = SharkordSession.describe(error)
                isError = true
            }
        }
    }

    private func pickImage(_ onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    private func upload(url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? await session.uploadAttachment(
            data: data,
            fileName: url.lastPathComponent,
            mimeType: "image/png"
        )
    }
}

struct PasswordSettingsView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("passwordTitle", ns: "settings"),
            subtitle: L10n.t("passwordDesc", ns: "settings"),
            onSave: save
        ) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsField(label: L10n.t("currentPasswordLabel", ns: "settings")) {
                    SecureField("", text: $current)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                SettingsField(label: L10n.t("newPasswordLabel", ns: "settings")) {
                    SecureField("", text: $new)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                SettingsField(label: L10n.t("confirmNewPasswordLabel", ns: "settings")) {
                    SecureField("", text: $confirm)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? .red : .green)
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                try await session.updatePassword(current: current, new: new, confirm: confirm)
                if session.loginCredentialsSaveFailed {
                    statusMessage = L10n.t("autoLoginPasswordUpdateFailed", ns: "macos")
                    isError = true
                } else {
                    statusMessage = L10n.t("passwordUpdated", ns: "settings")
                    isError = false
                }
                current = ""
                new = ""
                confirm = ""
            } catch {
                statusMessage = SharkordSession.describe(error)
                isError = true
            }
        }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var notifications: DesktopNotificationController
    @AppStorage("notify.allMessages") private var allMessages = false
    @AppStorage("notify.mentionsOnly") private var mentionsOnly = true
    @AppStorage("notify.dms") private var dms = true
    @AppStorage("notify.replies") private var replies = true

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("notificationsTitle", ns: "settings"),
            subtitle: L10n.t("notificationsDesc", ns: "settings")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.t("notificationPermissionTitle", ns: "settings"))
                            .font(.system(size: 12, weight: .medium))

                        Text(L10n.t(notifications.permissionDescriptionKey, ns: "settings"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        if notifications.requestFailed {
                            Text(L10n.t("notificationRequestFailed", ns: "macos"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()

                    if notifications.authorizationStatus == .denied {
                        Button(L10n.t("openSystemSettings", ns: "macos"), action: openNotificationSettings)
                    }
                }
                .padding(.bottom, 12)

                Toggle(L10n.t("allMessagesLabel", ns: "settings"), isOn: $allMessages)
                Text(L10n.t("allMessagesDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("mentionsOnlyLabel", ns: "settings"), isOn: $mentionsOnly)
                Text(L10n.t("mentionsOnlyDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("dmNotificationsLabel", ns: "settings"), isOn: $dms)
                Text(L10n.t("dmNotificationsDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("repliesNotificationsLabel", ns: "settings"), isOn: $replies)
                Text(L10n.t("repliesNotificationsDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
        }
        .onAppear {
            notifications.refreshAuthorization()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

struct OtherSettingsView: View {
    @EnvironmentObject private var pushToTalk: PushToTalkController
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.autoJoinLastChannel") private var autoJoin = true
    @AppStorage("app.appearance") private var appearance = "system"
    @AppStorage("voice.pushToTalkEnabled") private var pushToTalkEnabled = false
    @State private var language = L10n.language

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("othersTitle", ns: "settings"),
            subtitle: L10n.t("othersDesc", ns: "settings")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(L10n.t("autoJoinLastChannelLabel", ns: "settings"), isOn: $autoJoin)
                Text(L10n.t("autoJoinLastChannelDesc", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)

                SettingsField(
                    label: L10n.t("languageLabel", ns: "settings"),
                    help: L10n.t("languageDesc", ns: "settings")
                ) {
                    Picker("", selection: $language) {
                        ForEach(L10n.supportedLanguages, id: \.code) { entry in
                            Text(entry.nativeName).tag(entry.code)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .onChange(of: language) {
                        L10n.language = language
                    }
                }

                SettingsField(label: L10n.t("appearanceLabel", ns: "macos")) {
                    Picker(L10n.t("appearanceLabel", ns: "macos"), selection: $appearance) {
                        Text(L10n.t("appearanceSystem", ns: "macos")).tag("system")
                        Text(L10n.t("appearanceLight", ns: "macos")).tag("light")
                        Text(L10n.t("appearanceDark", ns: "macos")).tag("dark")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                Divider().padding(.vertical, 8)

                Toggle(L10n.t("pushToTalkTitle", ns: "macos"), isOn: $pushToTalkEnabled)
                    .onChange(of: pushToTalkEnabled) { _, enabled in
                        pushToTalk.setEnabled(enabled)
                    }

                Text(L10n.t("pushToTalkDesc", ns: "macos"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if pushToTalk.permissionRequired {
                    Text(L10n.t("pushToTalkPermissionRequired", ns: "macos"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)

                    Button(L10n.t("openSystemSettings", ns: "macos"), action: openInputMonitoringSettings)
                } else if pushToTalkEnabled {
                    Text(L10n.t("pushToTalkReady", ns: "macos"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            pushToTalk.restoreEnabled(pushToTalkEnabled)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, pushToTalkEnabled {
                pushToTalk.retryAfterPermissionChange()
            }
        }
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

struct KeyboardShortcutsSettingsView: View {
    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("keyboardShortcutsTitle", ns: "macos"),
            subtitle: L10n.t("keyboardShortcutsDescription", ns: "macos")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(KeyboardShortcutAction.allCases) { action in
                    KeyboardShortcutSettingsRow(action: action)
                    Divider()
                }
            }
        }
    }
}

private struct KeyboardShortcutSettingsRow: View {
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutsController

    let action: KeyboardShortcutAction

    @State private var assignmentError: KeyboardShortcutAssignmentError?

    private var binding: KeyboardShortcutBinding? {
        keyboardShortcuts.preferences.binding(for: action)
    }

    private var description: String {
        guard let descriptionKey = action.descriptionKey else {
            return ""
        }

        if action == .sendMessage {
            guard let binding else {
                return L10n.t("keyboardShortcutSendUnsetDescription", ns: "macos")
            }

            let shortcut = binding.displayString
            return L10n.t(descriptionKey, ns: "macos", ["shortcut": shortcut])
        }

        return L10n.t(descriptionKey, ns: "macos")
    }

    private var errorText: String? {
        switch assignmentError {
        case .modifierRequired:
            return L10n.t("keyboardShortcutModifierRequired", ns: "macos")
        case .returnReservedForNewline:
            return L10n.t("keyboardShortcutReturnReserved", ns: "macos")
        case .reservedForPushToTalk:
            return L10n.t("keyboardShortcutReservedForPushToTalk", ns: "macos")
        case .alreadyAssigned(let conflict):
            return L10n.t(
                "keyboardShortcutConflict",
                ns: "macos",
                ["action": L10n.t(conflict.titleKey, ns: "macos")]
            )
        case nil:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(action.titleKey, ns: "macos"))
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    assignmentError = nil
                    keyboardShortcuts.beginRecording(action)
                } label: {
                    Text(
                        keyboardShortcuts.recordingAction == action
                            ? L10n.t("keyboardShortcutPress", ns: "macos")
                            : binding?.displayString ?? L10n.t("keyboardShortcutNotSet", ns: "macos")
                    )
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 104, maxWidth: 190, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .disabled(keyboardShortcuts.recordingAction != nil && keyboardShortcuts.recordingAction != action)

                if keyboardShortcuts.recordingAction == action {
                    Text(L10n.t("keyboardShortcutCaptureHint", ns: "macos"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                } else if binding != nil {
                    Button(L10n.t("keyboardShortcutClear", ns: "macos")) {
                        assignmentError = nil
                        _ = keyboardShortcuts.assign(nil, to: action)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .disabled(keyboardShortcuts.recordingAction != nil)
                }
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .background {
            KeyboardShortcutCaptureView(
                isRecording: keyboardShortcuts.recordingAction == action,
                onCapture: { binding in
                    assignmentError = keyboardShortcuts.assign(binding, to: action)
                },
                onClear: {
                    assignmentError = nil
                    _ = keyboardShortcuts.assign(nil, to: action)
                },
                onCancel: keyboardShortcuts.cancelRecording
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}

private struct KeyboardShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (KeyboardShortcutBinding) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyboardShortcutCaptureNSView {
        KeyboardShortcutCaptureNSView()
    }

    func updateNSView(_ nsView: KeyboardShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        nsView.onCancel = onCancel

        if isRecording, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        } else if !isRecording, nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}

private final class KeyboardShortcutCaptureNSView: NSView {
    var onCapture: ((KeyboardShortcutBinding) -> Void)?
    var onClear: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 51, 117:
            onClear?()
        default:
            if let binding = KeyboardShortcutBinding(event: event) {
                onCapture?(binding)
            }
        }
    }
}
