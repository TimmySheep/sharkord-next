import Foundation
import Testing
@testable import SharkordCore

@MainActor
struct DesktopParityTests {
    private func parse(_ source: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }

    @Test func liveRepliesAreIsolatedAndUnpinRemovesCachedPin() throws {
        let session = SharkordSession()
        let root = try parse("""
        {"id":1,"channelId":7,"createdAt":10,"pinned":true}
        """).decode(SharkordMessage.self)
        let reply = try parse("""
        {"id":2,"channelId":7,"createdAt":11,"parentMessageId":1}
        """).decode(SharkordMessage.self)
        session.upsert(root, markUnread: false)
        session.upsert(reply, markUnread: false)
        #expect(session.messagesByChannel[7]?.map(\.id) == [1])
        #expect(session.threadMessages(for: 1).map(\.id) == [2])
        #expect(session.pinnedMessages(in: 7).map(\.id) == [1])
        let unpinned = try parse("""
        {"id":1,"channelId":7,"createdAt":10,"pinned":false}
        """).decode(SharkordMessage.self)
        session.upsert(unpinned, markUnread: false)
        #expect(session.pinnedMessages(in: 7).isEmpty)
        session.removeMessage(id: 1, channelId: 7)
        #expect(session.threadMessages(for: 1).isEmpty)
    }

    @Test func threadPagesKeepCursorAndDoNotEnterChannelTimeline() throws {
        let session = SharkordSession()
        let first = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100}],
         "nextCursor":{"id":11,"createdAt":100}}
        """).decode(ThreadPage.self)
        session.applyThreadPage(first, parentMessageId: 1)
        #expect(session.threadNextCursor[1]?.id == 11)
        let next = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100},
                     {"id":12,"channelId":7,"parentMessageId":1,"createdAt":100}],"nextCursor":null}
        """).decode(ThreadPage.self)
        session.applyThreadPage(next, parentMessageId: 1)
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
        session.threadMessages[7] = []
        session.apply(modern)
        #expect(session.usesJoinedDirectMessages)
        #expect(session.directMessages.isEmpty)
        #expect(session.threadMessages.isEmpty)
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
        session.usesJoinedDirectMessages = true
        session.channels = try parse("""
        [{"id":7,"name":"DM - 1:2","type":"VOICE","private":true,"isDm":true,"position":0,"createdAt":0}]
        """).decode([SharkordChannel].self)
        session.applyConversation(old)
        #expect(session.directMessages.map(\.channelId) == [7])
        #expect(session.directMessageChannels.map(\.id) == [7])
        session.applyConversation(modern)
        #expect(session.directMessages.isEmpty)
        #expect(session.directMessageChannels.isEmpty)
    }

    @Test func searchRetainsThreadParentForNavigation() throws {
        let message = try parse("""
        {"id":12,"channelId":7,"channelName":"chat","channelIsDm":false,
         "parentMessageId":1,"createdAt":100}
        """).decode(SearchMessage.self)
        #expect(message.navigationMessageId == 1)
    }
}
