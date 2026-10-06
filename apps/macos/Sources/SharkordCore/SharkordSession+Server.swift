import Foundation

/// Server level administration: settings, logo, storage, updates and the ownership token.
extension SharkordSession {
    @discardableResult
    public func getSettings() async throws -> SharkordAdminSettings {
        try await call("others.getSettings", method: .query).decode(SharkordAdminSettings.self)
    }

    /// `others.updateSettings` accepts only the keys being changed. Passing an empty object
    /// is a `BAD_REQUEST`, so build the object from the non-nil arguments.
    public func updateSettings(_ values: [String: JSONValue]) async throws {
        guard !values.isEmpty else {
            return
        }

        _ = try await call("others.updateSettings", method: .mutation, input: .object(values))
        try? await refreshPublicSettings()
    }

    public func changeLogo(fileId: String?) async throws {
        var input: [String: JSONValue] = [:]

        if let fileId {
            input["fileId"] = .string(fileId)
        }

        _ = try await call("others.changeLogo", method: .mutation, input: .object(input))
    }

    @discardableResult
    public func getStorageSettings() async throws -> StorageSettingsResult {
        try await call("others.getStorageSettings", method: .query).decode(StorageSettingsResult.self)
    }

    @discardableResult
    public func getUpdate() async throws -> UpdateInfo {
        try await call("others.getUpdate", method: .query).decode(UpdateInfo.self)
    }

    public func updateServer() async throws {
        _ = try await call("others.updateServer", method: .mutation)
    }

    /// Grants the owner role from the printed first-run token. Returns false when the token
    /// is wrong or the viewer is already an owner, so callers can ignore it silently.
    @discardableResult
    public func useSecretToken(_ token: String) async throws -> Bool {
        do {
            _ = try await call(
                "others.useSecretToken",
                method: .mutation,
                input: .object(["token": .string(token)])
            )

            return true
        } catch let error as TRPCClientError where error.code == "CONFLICT" {
            return false
        }
    }

    func refreshPublicSettings() async throws {
        let settings = try await getSettings()

        self.settings = SharkordSettings(
            name: settings.name,
            description: settings.description,
            serverId: settings.serverId,
            storageUploadEnabled: settings.storageUploadEnabled,
            directMessagesEnabled: settings.directMessagesEnabled,
            storageQuota: settings.storageQuota,
            storageUploadMaxFileSize: settings.storageUploadMaxFileSize,
            storageFileSharingInDirectMessages: settings.storageFileSharingInDirectMessages,
            storageMaxFilesPerMessage: settings.storageMaxFilesPerMessage,
            storageMaxAvatarSize: settings.storageMaxAvatarSize,
            storageMaxBannerSize: settings.storageMaxBannerSize,
            storageSpaceQuotaByUser: settings.storageSpaceQuotaByUser,
            storageOverflowAction: settings.storageOverflowAction,
            enablePlugins: settings.enablePlugins,
            enableSearch: settings.enableSearch,
            storageSignedUrlsEnabled: settings.storageSignedUrlsEnabled,
            webRtcSimulcastEnabled: settings.webRtcSimulcastEnabled,
            webRtcMaxBitrate: self.settings?.webRtcMaxBitrate,
            showWelcomeDialog: settings.showWelcomeDialog
        )
    }
}
