import Foundation
import Testing
@testable import SharkordCore

@MainActor
struct DesktopParityTests {
    private func parse(_ source: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }

    @Test func threadPagesKeepCursorAndDoNotEnterChannelTimeline() throws {
        let session = SharkordSession()
        let first = try parse("""
        {"messages":[{"id":12,"channelId":7,"parentMessageId":1,"createdAt":100}],
         "nextCursor":{"id":12,"createdAt":100}}
        """).decode(ThreadPage.self)
        session.applyThreadPage(first, parentMessageId: 1)
        #expect(session.threadNextCursor[1]?.id == 12)
        let older = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100},
                     {"id":12,"channelId":7,"parentMessageId":1,"createdAt":100}],"nextCursor":null}
        """).decode(ThreadPage.self)
        session.applyThreadPage(older, parentMessageId: 1)
        #expect(session.threadMessages(for: 1).map(\.id) == [11, 12])
        #expect(session.threadNextCursor[1] == nil)
        #expect(session.messagesByChannel[7] == nil)
        session.removeMessage(id: 12, channelId: 7)
        #expect(session.threadMessages(for: 1).map(\.id) == [11])
    }

    @Test func dmProtocolUsesJoinPresenceIncludingEmptyList() throws {
        let base = """
        "categories":[],"channels":[],"users":[],"roles":[],"serverId":"test",
        "serverName":"test","ownUserId":1,"publicSettings":{"name":"test","serverId":"test"}
        """
        let legacy = try parse("{\(base)}").decode(JoinResult.self)
        let modern = try parse("{\(base),\"directMessages\":[]}").decode(JoinResult.self)
        let session = SharkordSession()
        session.apply(legacy)
        #expect(!session.usesJoinedDirectMessages)
        session.apply(modern)
        #expect(session.usesJoinedDirectMessages)
        #expect(session.directMessages.isEmpty)
    }

    @Test func dmEntriesDecodeOldUnreadCountAndNewClosedState() throws {
        let old = try parse("""
        {"channelId":7,"userId":2,"unreadCount":3,"lastMessageAt":100}
        """).decode(DirectMessageConversation.self)
        #expect(old.unreadCount == 3)
        #expect(old.closedAt == nil)
        let modern = try parse("""
        {"channelId":7,"userId":2,"lastMessageAt":100,"closedAt":200}
        """).decode(DirectMessageConversation.self)
        #expect(modern.unreadCount == 0)
        #expect(modern.closedAt == 200)
        let session = SharkordSession()
        session.applyConversation(old)
        #expect(session.directMessages.map(\.channelId) == [7])
        session.applyConversation(modern)
        #expect(session.directMessages.isEmpty)
    }

    @Test func searchRetainsThreadParentForNavigation() throws {
        let message = try parse("""
        {"id":12,"channelId":7,"channelName":"chat","channelIsDm":false,
         "parentMessageId":1,"createdAt":100}
        """).decode(SearchMessage.self)
        #expect(message.navigationMessageId == 1)
    }
}
