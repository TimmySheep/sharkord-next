import AppKit
import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeProfileSetupView: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bio = ""
    @State private var profileColor = "#1447E6"
    @State private var avatarFileId: String?
    @State private var bannerFileId: String?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isUploadingImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("welcomeProfileSetupTitle", ns: "dialogs", ["serverName": session.serverName]))
                .font(.title2.bold())

            Text(L10n.t("welcomeProfileSetupDesc", ns: "dialogs"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                AvatarView(user: session.ownUser, size: 64)

                Button(L10n.t("avatarLabel", ns: "settings")) {
                    chooseImage { url in
                        uploadImage(url, isAvatar: true)
                    }
                }
                .disabled(isUploadingImage || isSaving)

                Button(L10n.t("bannerLabel", ns: "settings")) {
                    chooseImage { url in
                        uploadImage(url, isAvatar: false)
                    }
                }
                .disabled(isUploadingImage || isSaving)
            }

            TextField(L10n.t("usernameLabel", ns: "settings"), text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField(L10n.t("profileColorLabel", ns: "settings"), text: $profileColor)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                ColorPicker("", selection: Binding(
                    get: { Color(hex: profileColor) ?? Theme.accent },
                    set: { profileColor = $0.hexString }
                ))
                .labelsHidden()
            }

            TextEditor(text: $bio)
                .frame(minHeight: 76, maxHeight: 100)
                .overlay(alignment: .topLeading) {
                    if bio.isEmpty {
                        Text(L10n.t("bioLabel", ns: "settings"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(L10n.t("bioLabel", ns: "settings"))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.t("cancel", ns: "common")) {
                    dismiss()
                }

                Spacer()

                Button(L10n.t("saveChanges", ns: "settings"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isUploadingImage || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
        .onAppear {
            name = session.ownUser?.name ?? ""
            bio = session.ownUser?.bio ?? ""
            profileColor = session.ownUser?.profileColor ?? "#1447E6"
        }
    }

    private func save() {
        guard !isSaving else {
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.updateProfile(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    profileColor: profileColor,
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bio
                )

                if let avatarFileId {
                    try await session.changeAvatar(fileId: avatarFileId)
                }

                if let bannerFileId {
                    try await session.changeBanner(fileId: bannerFileId)
                }

                dismiss()
            } catch {
                errorMessage = SharkordSession.describe(error)
            }

            isSaving = false
        }
    }

    private func chooseImage(_ onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    private func upload(_ url: URL) async -> String? {
        do {
            let data = try Data(contentsOf: url)
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            return try await session.uploadAttachment(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: mimeType
            )
        } catch {
            errorMessage = SharkordSession.describe(error)
            return nil
        }
    }

    private func uploadImage(_ url: URL, isAvatar: Bool) {
        guard !isUploadingImage, !isSaving else {
            return
        }

        isUploadingImage = true

        Task {
            let fileId = await upload(url)

            if isAvatar {
                avatarFileId = fileId
            } else {
                bannerFileId = fileId
            }

            isUploadingImage = false
        }
    }
}
