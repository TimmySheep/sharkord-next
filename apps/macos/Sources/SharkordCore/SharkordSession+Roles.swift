import Foundation

/// Role administration. Role 1 is the owner role and behaves specially everywhere.
extension SharkordSession {
    @discardableResult
    public func addRole() async throws -> Int {
        try await call("roles.add", method: .mutation).intValue ?? 0
    }

    public func updateRole(_ update: RoleUpdate) async throws {
        _ = try await call(
            "roles.update",
            method: .mutation,
            input: .object([
                "roleId": .int(update.roleId),
                "name": .string(update.name),
                "color": .string(update.color),
                "permissions": .array(update.permissions.map { .string($0) }),
                "storageQuotaOverrideEnabled": .bool(update.storageQuotaOverrideEnabled),
                "storageSpaceQuota": .int(update.storageSpaceQuota)
            ])
        )
    }

    public func deleteRole(roleId: Int) async throws {
        _ = try await call(
            "roles.delete",
            method: .mutation,
            input: .object(["roleId": .int(roleId)])
        )
    }

    public func setDefaultRole(roleId: Int) async throws {
        _ = try await call(
            "roles.setDefault",
            method: .mutation,
            input: .object(["roleId": .int(roleId)])
        )
    }

    @discardableResult
    public func getAllRoles() async throws -> [SharkordRole] {
        try await call("roles.getAll", method: .query).decode([SharkordRole].self)
    }
}
