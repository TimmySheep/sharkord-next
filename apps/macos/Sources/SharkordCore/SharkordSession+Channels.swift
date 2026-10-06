import Foundation

/// Category and channel administration, channel permissions and read receipts.
extension SharkordSession {
    // MARK: categories

    @discardableResult
    public func addCategory(name: String) async throws -> Int {
        try await call(
            "categories.add",
            method: .mutation,
            input: .object(["name": .string(name)])
        ).intValue ?? 0
    }

    public func updateCategory(categoryId: Int, name: String) async throws {
        _ = try await call(
            "categories.update",
            method: .mutation,
            input: .object([
                "categoryId": .int(categoryId),
                "name": .string(name)
            ])
        )
    }

    public func deleteCategory(categoryId: Int) async throws {
        _ = try await call(
            "categories.delete",
            method: .mutation,
            input: .object(["categoryId": .int(categoryId)])
        )
    }

    public func getCategory(categoryId: Int) async throws -> SharkordCategory {
        try await call(
            "categories.get",
            method: .query,
            input: .object(["categoryId": .int(categoryId)])
        ).decode(SharkordCategory.self)
    }

    public func reorderCategories(categoryIds: [Int]) async throws {
        _ = try await call(
            "categories.reorder",
            method: .mutation,
            input: .object(["categoryIds": .array(categoryIds.map { .int($0) })])
        )
    }

    // MARK: channels

    @discardableResult
    public func addChannel(type: ChannelType, name: String, categoryId: Int) async throws -> Int {
        try await call(
            "channels.add",
            method: .mutation,
            input: .object([
                "type": .string(type.rawValue),
                "name": .string(name),
                "categoryId": .int(categoryId)
            ])
        ).intValue ?? 0
    }

    public func updateChannel(
        channelId: Int,
        name: String? = nil,
        topic: String? = nil,
        isPrivate: Bool? = nil
    ) async throws {
        var input: [String: JSONValue] = ["channelId": .int(channelId)]

        if let name {
            input["name"] = .string(name)
        }

        if let topic {
            input["topic"] = topic.isEmpty ? .null : .string(topic)
        }

        if let isPrivate {
            input["private"] = .bool(isPrivate)
        }

        _ = try await call("channels.update", method: .mutation, input: .object(input))
    }

    public func deleteChannel(channelId: Int) async throws {
        _ = try await call(
            "channels.delete",
            method: .mutation,
            input: .object(["channelId": .int(channelId)])
        )
    }

    public func getChannel(channelId: Int) async throws -> SharkordChannel {
        try await call(
            "channels.get",
            method: .query,
            input: .object(["channelId": .int(channelId)])
        ).decode(SharkordChannel.self)
    }

    public func reorderChannels(categoryId: Int, channelIds: [Int]) async throws {
        _ = try await call(
            "channels.reorder",
            method: .mutation,
            input: .object([
                "categoryId": .int(categoryId),
                "channelIds": .array(channelIds.map { .int($0) })
            ])
        )
    }

    // MARK: channel permissions

    /// `isCreate` writes the all-false base row; without it the listed permissions become
    /// the allowed set for that role or user.
    public func updateChannelPermissions(_ update: ChannelPermissionUpdate) async throws {
        var input: [String: JSONValue] = ["channelId": .int(update.channelId)]

        if let userId = update.userId {
            input["userId"] = .int(userId)
        }

        if let roleId = update.roleId {
            input["roleId"] = .int(roleId)
        }

        if let isCreate = update.isCreate {
            input["isCreate"] = .bool(isCreate)
        }

        if let permissions = update.permissions {
            input["permissions"] = .array(permissions.map { .string($0.rawValue) })
        }

        _ = try await call("channels.updatePermissions", method: .mutation, input: .object(input))
    }

    @discardableResult
    public func getChannelPermissions(channelId: Int) async throws -> ChannelPermissionsResult {
        try await call(
            "channels.getPermissions",
            method: .query,
            input: .object(["channelId": .int(channelId)])
        ).decode(ChannelPermissionsResult.self)
    }

    public func deleteChannelPermissions(
        channelId: Int,
        userId: Int? = nil,
        roleId: Int? = nil
    ) async throws {
        var input: [String: JSONValue] = ["channelId": .int(channelId)]

        if let userId {
            input["userId"] = .int(userId)
        }

        if let roleId {
            input["roleId"] = .int(roleId)
        }

        _ = try await call("channels.deletePermissions", method: .mutation, input: .object(input))
    }

    // MARK: read receipts

    public func markAsRead(_ channelId: Int) {
        clearUnread(channelId)

        guard let client else {
            return
        }

        Task {
            _ = try? await client.mutation(
                "channels.markAsRead",
                input: .object(["channelId": .int(channelId)])
            )
        }
    }
}
