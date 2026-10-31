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
        #expect(session.deletedMessage?.messageId == 1)
        #expect(session.deletedMessage?.channelId == 7)
    }

    @Test func threadPagesKeepCursorAndDoNotEnterChannelTimeline() throws {
        let session = SharkordSession()
        let first = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100}],
         "nextCursor":{"id":11,"createdAt":100}}
        """).decode(ThreadPage.self)
        let firstRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = firstRequest
        try session.applyThreadPage(first, parentMessageId: 1, requestId: firstRequest.id)
        #expect(session.threadNextCursor[1]?.id == 11)
        let next = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100},
                     {"id":12,"channelId":7,"parentMessageId":1,"createdAt":100}],"nextCursor":null}
        """).decode(ThreadPage.self)
        let nextRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = nextRequest
        try session.applyThreadPage(next, parentMessageId: 1, requestId: nextRequest.id)
        #expect(session.threadMessages(for: 1).map(\.id) == [11, 12])
        #expect(session.threadNextCursor[1] == nil)
        #expect(session.messagesByChannel[7] == nil)
        session.removeMessage(id: 12, channelId: 7)
        #expect(session.threadMessages(for: 1).map(\.id) == [11])
    }

    @Test func staleThreadPageCannotOverwriteReopenedThread() throws {
        let session = SharkordSession()
        let oldRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = oldRequest
        session.cancelThreadLoad(parentMessageId: 1)
        let newRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = newRequest
        let fresh = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100,"content":"new"}],
         "nextCursor":{"id":11,"createdAt":100}}
        """).decode(ThreadPage.self)
        try session.applyThreadPage(fresh, parentMessageId: 1, requestId: newRequest.id)
        let stale = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100,"content":"old"}],"nextCursor":null}
        """).decode(ThreadPage.self)
        #expect(throws: CancellationError.self) {
            try session.applyThreadPage(stale, parentMessageId: 1, requestId: oldRequest.id)
        }
        #expect(session.threadMessages(for: 1).first?.content == "new")
        #expect(session.threadNextCursor[1]?.id == 11)
    }

    @Test func rootDeletionRejectsPendingThreadPage() throws {
        let session = SharkordSession()
        let request = SharkordSession.ThreadRequest()
        session.threadRequests[1] = request
        let page = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100}],
         "nextCursor":{"id":11,"createdAt":100}}
        """).decode(ThreadPage.self)
        session.removeMessage(id: 1, channelId: 7)
        #expect(throws: CancellationError.self) {
            try session.applyThreadPage(page, parentMessageId: 1, requestId: request.id)
        }
        #expect(session.threadMessages(for: 1).isEmpty)
        #expect(session.threadNextCursor[1] == nil)
    }

    @Test func liveReplyChangesWinOverPendingThreadSnapshot() throws {
        let session = SharkordSession()
        let request = SharkordSession.ThreadRequest()
        session.threadRequests[1] = request
        session.upsert(try parse("""
        {"id":11,"channelId":7,"parentMessageId":1,"createdAt":100,"content":"edited"}
        """).decode(SharkordMessage.self), markUnread: false)
        session.removeMessage(id: 12, channelId: 7)
        let page = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100,"content":"old"},
                     {"id":12,"channelId":7,"parentMessageId":1,"createdAt":101}],"nextCursor":null}
        """).decode(ThreadPage.self)
        try session.applyThreadPage(page, parentMessageId: 1, requestId: request.id)
        #expect(session.threadMessages(for: 1).map(\.id) == [11])
        #expect(session.threadMessages(for: 1).first?.content == "edited")
    }

    @Test func closingOrDisconnectingThreadInvalidatesItsRequest() throws {
        let session = SharkordSession()
        let page = try parse("""
        {"messages":[],"nextCursor":{"id":11,"createdAt":100}}
        """).decode(ThreadPage.self)
        let closedRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = closedRequest
        session.cancelThreadLoad(parentMessageId: 1)
        #expect(throws: CancellationError.self) {
            try session.applyThreadPage(page, parentMessageId: 1, requestId: closedRequest.id)
        }
        let disconnectedRequest = SharkordSession.ThreadRequest()
        session.threadRequests[1] = disconnectedRequest
        session.disconnect()
        #expect(throws: CancellationError.self) {
            try session.applyThreadPage(page, parentMessageId: 1, requestId: disconnectedRequest.id)
        }
        #expect(session.threadNextCursor.isEmpty)
    }

    @Test func cancelledThreadTaskCannotApplyPage() async throws {
        let session = SharkordSession()
        let request = SharkordSession.ThreadRequest()
        session.threadRequests[1] = request
        let page = try parse("""
        {"messages":[{"id":11,"channelId":7,"parentMessageId":1,"createdAt":100}],"nextCursor":null}
        """).decode(ThreadPage.self)
        let task = Task { @MainActor in
            try session.applyThreadPage(page, parentMessageId: 1, requestId: request.id)
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("cancelled thread page was applied")
        } catch is CancellationError {
            #expect(session.threadMessages(for: 1).isEmpty)
        }
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
        let request = SharkordSession.ThreadRequest()
        session.threadRequests[7] = request
        session.apply(modern)
        #expect(session.usesJoinedDirectMessages)
        #expect(session.directMessages.isEmpty)
        #expect(session.threadMessages.isEmpty)
        #expect(session.threadRequests.isEmpty)
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
