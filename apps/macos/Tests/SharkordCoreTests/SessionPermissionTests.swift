import Foundation
import Testing

@testable import SharkordCore

struct SessionPermissionTests {
    @Test
    @MainActor
    func ownerRoleHasEveryGlobalPermissionWithoutRoleEntries() throws {
        let session = SharkordSession()
        session.ownUserId = 1
        session.users = [try Self.user(id: 1, roleIds: [ProtocolDefaults.ownerRoleId])]
        session.roles = [try Self.role(id: ProtocolDefaults.ownerRoleId, permissions: [])]

        #expect(session.hasPermission(.joinVoiceChannels))
        #expect(session.hasPermission(.enableWebcam))
        #expect(session.hasPermission(.shareScreen))
    }

    @Test
    @MainActor
    func regularRoleStillRequiresExplicitGlobalPermission() throws {
        let session = SharkordSession()
        session.ownUserId = 2
        session.users = [try Self.user(id: 2, roleIds: [2])]
        session.roles = [try Self.role(id: 2, permissions: [Permission.joinVoiceChannels.rawValue])]

        #expect(session.hasPermission(.joinVoiceChannels))
        #expect(!session.hasPermission(.enableWebcam))
    }

    @Test
    @MainActor
    func missingChannelPermissionMapUsesPublicChannelAndOwnerDefaults() throws {
        let session = SharkordSession()
        let publicChannel = try Self.channel(id: 10, isPrivate: false)
        let privateChannel = try Self.channel(id: 11, isPrivate: true)
        session.channels = [publicChannel, privateChannel]

        #expect(session.hasChannelPermission(publicChannel.id, .join))
        #expect(!session.hasChannelPermission(privateChannel.id, .join))

        session.ownUserId = 1
        session.users = [try Self.user(id: 1, roleIds: [ProtocolDefaults.ownerRoleId])]

        #expect(session.hasChannelPermission(privateChannel.id, .join))
    }

    @Test
    @MainActor
    func channelPermissionMapDecodesTheServerRecordShape() throws {
        let session = SharkordSession()
        let channel = try Self.channel(id: 10, isPrivate: true)
        let permissions = try JSONDecoder().decode(
            ChannelPermissionsMap.self,
            from: JSONSerialization.data(withJSONObject: [
                "10": [
                    "channelId": 10,
                    "permissions": [ChannelPermission.join.rawValue: true]
                ]
            ])
        )
        session.channels = [channel]
        session.channelPermissions = permissions

        #expect(session.hasChannelPermission(channel.id, .join))
        #expect(!session.hasChannelPermission(channel.id, .speak))
    }

    @Test
    @MainActor
    func publicChannelsAndOwnerIgnoreDefaultDenyRows() throws {
        let session = SharkordSession()
        session.channels = [try Self.channel(id: 10, isPrivate: false), try Self.channel(id: 11, isPrivate: true)]
        let denied = Dictionary(uniqueKeysWithValues: ChannelPermission.allCases.map { ($0.rawValue, false) })
        session.channelPermissions = .init(entries: [
            10: .init(channelId: 10, permissions: denied),
            11: .init(channelId: 11, permissions: denied)
        ])

        for permission in ChannelPermission.allCases {
            #expect(session.hasChannelPermission(10, permission))
            #expect(!session.hasChannelPermission(11, permission))
        }

        session.ownUserId = 1
        session.users = [try Self.user(id: 1, roleIds: [ProtocolDefaults.ownerRoleId])]
        for permission in ChannelPermission.allCases {
            #expect(session.hasChannelPermission(11, permission))
            #expect(!session.hasChannelPermission(999, permission))
        }
    }

    @Test
    @MainActor
    func invisiblePrivateChannelDeniesOtherPermissions() throws {
        let session = SharkordSession()
        session.channels = [try Self.channel(id: 10, isPrivate: true)]
        session.channelPermissions = .init(entries: [10: .init(channelId: 10, permissions: [
            ChannelPermission.viewChannel.rawValue: false,
            ChannelPermission.join.rawValue: true,
            ChannelPermission.sendMessages.rawValue: true
        ])])
        #expect(!session.hasChannelPermission(10, .join))
        #expect(!session.hasChannelPermission(10, .sendMessages))
    }

    private static func user(id: Int, roleIds: [Int]) throws -> SharkordUser {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "name": "user-\(id)",
            "profileColor": "#ffffff",
            "banned": false,
            "createdAt": 0,
            "roleIds": roleIds
        ])

        return try JSONDecoder().decode(SharkordUser.self, from: data)
    }

    private static func role(id: Int, permissions: [String]) throws -> SharkordRole {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "name": "role-\(id)",
            "color": "#ffffff",
            "isPersistent": true,
            "isDefault": false,
            "permissions": permissions,
            "createdAt": 0
        ])

        return try JSONDecoder().decode(SharkordRole.self, from: data)
    }

    private static func channel(id: Int, isPrivate: Bool) throws -> SharkordChannel {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "type": ChannelType.voice.rawValue,
            "name": "voice-\(id)",
            "private": isPrivate,
            "isDm": false,
            "position": 0,
            "createdAt": 0
        ])

        return try JSONDecoder().decode(SharkordChannel.self, from: data)
    }
}
