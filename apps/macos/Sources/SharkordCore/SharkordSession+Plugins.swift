import Foundation

/// Plugin management and the plugin runtime API the web client exposes to plugin UI.
extension SharkordSession {
    // MARK: management

    @discardableResult
    public func getPlugins() async throws -> [PluginInfo] {
        try await call("plugins.get", method: .query)
            .decode(PluginsResult.self)
            .plugins
    }

    public func togglePlugin(pluginId: String, enabled: Bool) async throws {
        _ = try await call(
            "plugins.toggle",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "enabled": .bool(enabled)
            ])
        )
    }

    public func installPlugin(pluginId: String, version: String) async throws {
        _ = try await call(
            "plugins.install",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "version": .string(version)
            ])
        )
    }

    public func updatePlugin(pluginId: String, version: String) async throws {
        _ = try await call(
            "plugins.update",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "version": .string(version)
            ])
        )
    }

    public func removePlugin(pluginId: String) async throws {
        _ = try await call(
            "plugins.remove",
            method: .mutation,
            input: .object(["pluginId": .string(pluginId)])
        )
    }

    @discardableResult
    public func getPluginLogs(pluginId: String) async throws -> [PluginLogEntry] {
        try await call(
            "plugins.getLogs",
            method: .query,
            input: .object(["pluginId": .string(pluginId)])
        ).decode([PluginLogEntry].self)
    }

    @discardableResult
    public func getPluginCommands(pluginId: String?) async throws -> PluginCommandsMap {
        var input: [String: JSONValue] = [:]

        if let pluginId {
            input["pluginId"] = .string(pluginId)
        }

        return try await call("plugins.getCommands", method: .query, input: .object(input))
            .decode(PluginCommandsMap.self)
    }

    // MARK: capability access

    @discardableResult
    public func getPluginCapabilities(pluginId: String) async throws -> [PluginCapability] {
        try await call(
            "plugins.getCapabilities",
            method: .query,
            input: .object(["pluginId": .string(pluginId)])
        ).decode(PluginCapabilitiesResult.self).capabilities
    }

    public func setPluginCapabilityAccess(
        pluginId: String,
        type: String,
        name: String,
        mode: String,
        roleIds: [Int]
    ) async throws {
        _ = try await call(
            "plugins.setCapabilityAccess",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "type": .string(type),
                "name": .string(name),
                "mode": .string(mode),
                "roleIds": .array(roleIds.map { .int($0) })
            ])
        )
    }

    public func resetPluginCapabilityAccess(pluginId: String, type: String, name: String) async throws {
        _ = try await call(
            "plugins.resetCapabilityAccess",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "type": .string(type),
                "name": .string(name)
            ])
        )
    }

    // MARK: settings

    @discardableResult
    public func getPluginSettings(pluginId: String) async throws -> PluginSettings {
        try await call(
            "plugins.getSettings",
            method: .query,
            input: .object(["pluginId": .string(pluginId)])
        ).decode(PluginSettings.self)
    }

    public func updatePluginSetting(pluginId: String, key: String, value: JSONValue) async throws {
        _ = try await call(
            "plugins.updateSetting",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "key": .string(key),
                "value": value
            ])
        )
    }

    // MARK: runtime api

    @discardableResult
    public func getPluginUserData(pluginId: String) async throws -> [String: JSONValue] {
        try await call(
            "plugins.getUserData",
            method: .query,
            input: .object(["pluginId": .string(pluginId)])
        ).objectValue ?? [:]
    }

    public func setPluginUserData(pluginId: String, data: [String: JSONValue]) async throws {
        _ = try await call(
            "plugins.setUserData",
            method: .mutation,
            input: .object([
                "pluginId": .string(pluginId),
                "data": .object(data)
            ])
        )
    }

    @discardableResult
    public func executePluginCommand(
        pluginId: String,
        commandName: String,
        args: [String: JSONValue]? = nil,
        channelId: Int? = nil
    ) async throws -> JSONValue {
        var input: [String: JSONValue] = [
            "pluginId": .string(pluginId),
            "commandName": .string(commandName)
        ]

        if let args {
            input["args"] = .object(args)
        }

        if let channelId {
            input["channelId"] = .int(channelId)
        }

        return try await call("plugins.executeCommand", method: .mutation, input: .object(input))
    }

    @discardableResult
    public func executePluginAction(
        pluginId: String,
        actionName: String,
        payload: JSONValue? = nil,
        channelId: Int? = nil
    ) async throws -> JSONValue {
        var input: [String: JSONValue] = [
            "pluginId": .string(pluginId),
            "actionName": .string(actionName)
        ]

        if let payload {
            input["payload"] = payload
        }

        if let channelId {
            input["channelId"] = .int(channelId)
        }

        return try await call("plugins.executeAction", method: .mutation, input: .object(input))
    }
}

struct PluginsResult: Codable, Sendable {
    let plugins: [PluginInfo]
}

struct PluginCapabilitiesResult: Codable, Sendable {
    let capabilities: [PluginCapability]
}
