import Foundation

/// Invite links.
extension SharkordSession {
    @discardableResult
    public func createInvite(_ create: InviteCreate) async throws -> SharkordInvite {
        var input: [String: JSONValue] = [:]

        if let maxUses = create.maxUses {
            input["maxUses"] = .int(maxUses)
        }

        if let expiresAt = create.expiresAt {
            input["expiresAt"] = .int(expiresAt)
        }

        if let code = create.code {
            input["code"] = .string(code)
        }

        if let roleId = create.roleId {
            input["roleId"] = .int(roleId)
        }

        return try await call("invites.add", method: .mutation, input: .object(input))
            .decode(SharkordInvite.self)
    }

    public func deleteInvite(inviteId: Int) async throws {
        _ = try await call(
            "invites.delete",
            method: .mutation,
            input: .object(["inviteId": .int(inviteId)])
        )
    }

    @discardableResult
    public func getAllInvites() async throws -> [SharkordInvite] {
        try await call("invites.getAll", method: .query).decode([SharkordInvite].self)
    }

    /// The URL an invite code resolves to, matching the web client's join route.
    public func inviteURL(code: String) -> String? {
        guard let host = http?.baseURL.absoluteString else {
            return nil
        }

        return "\(host)?invite=\(code)"
    }
}
