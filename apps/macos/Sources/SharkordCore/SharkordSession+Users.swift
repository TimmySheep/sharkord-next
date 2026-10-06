import Foundation

/// User profile, moderation and role assignment.
extension SharkordSession {
    // MARK: own profile

    public func updateProfile(name: String, profileColor: String, bio: String?) async throws {
        var input: [String: JSONValue] = [
            "name": .string(name),
            "profileColor": .string(profileColor)
        ]

        if let bio {
            input["bio"] = .string(bio)
        }

        _ = try await call("users.update", method: .mutation, input: .object(input))
    }

    public func updatePassword(current: String, new: String, confirm: String) async throws {
        _ = try await call(
            "users.updatePassword",
            method: .mutation,
            input: .object([
                "currentPassword": .string(current),
                "newPassword": .string(new),
                "confirmNewPassword": .string(confirm)
            ])
        )

        ownUserPasswordSet = true
    }

    /// `fileId` is a temporary upload id; passing nil removes the image.
    public func changeAvatar(fileId: String?) async throws {
        try await changeUserImage(path: "users.changeAvatar", fileId: fileId)
    }

    public func changeBanner(fileId: String?) async throws {
        try await changeUserImage(path: "users.changeBanner", fileId: fileId)
    }

    private func changeUserImage(path: String, fileId: String?) async throws {
        var input: [String: JSONValue] = [:]

        if let fileId {
            input["fileId"] = .string(fileId)
        }

        _ = try await call(path, method: .mutation, input: .object(input))
    }

    // MARK: admin view

    @discardableResult
    public func getUserInfo(userId: Int) async throws -> UserDetail {
        try await call(
            "users.getInfo",
            method: .query,
            input: .object(["userId": .int(userId)])
        ).decode(UserDetail.self)
    }

    @discardableResult
    public func getAllUsers() async throws -> [SharkordAdminUser] {
        try await call("users.getAll", method: .query).decode([SharkordAdminUser].self)
    }

    // MARK: moderation

    public func kickUser(userId: Int, reason: String?) async throws {
        try await moderate("users.kick", userId: userId, reason: reason)
    }

    public func banUser(userId: Int, reason: String?) async throws {
        try await moderate("users.ban", userId: userId, reason: reason)
    }

    public func unbanUser(userId: Int) async throws {
        _ = try await call(
            "users.unban",
            method: .mutation,
            input: .object(["userId": .int(userId)])
        )
    }

    public func deleteUser(userId: Int, wipe: Bool) async throws {
        _ = try await call(
            "users.delete",
            method: .mutation,
            input: .object([
                "userId": .int(userId),
                "wipe": .bool(wipe)
            ])
        )
    }

    private func moderate(_ path: String, userId: Int, reason: String?) async throws {
        var input: [String: JSONValue] = ["userId": .int(userId)]

        if let reason, !reason.isEmpty {
            input["reason"] = .string(reason)
        }

        _ = try await call(path, method: .mutation, input: .object(input))
    }

    // MARK: role assignment

    public func addRole(userId: Int, roleId: Int) async throws {
        _ = try await call(
            "users.addRole",
            method: .mutation,
            input: .object([
                "userId": .int(userId),
                "roleId": .int(roleId)
            ])
        )
    }

    public func removeRole(userId: Int, roleId: Int) async throws {
        _ = try await call(
            "users.removeRole",
            method: .mutation,
            input: .object([
                "userId": .int(userId),
                "roleId": .int(roleId)
            ])
        )
    }
}
