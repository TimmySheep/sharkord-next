import Foundation
import Testing
@testable import SharkordCore

struct MessageTimelineTests {
    @Test func groupingUsesAuthorPluginReplyAndMinuteBoundaries() throws {
        let first = try message(id: 1, time: 1_000)
        #expect(MessageTimeline.isGrouped(try message(id: 2, time: 60_999), after: first))
        #expect(!MessageTimeline.isGrouped(try message(id: 2, time: 61_000), after: first))
        #expect(!MessageTimeline.isGrouped(try message(id: 2, time: 2_000, userId: 2), after: first))
        #expect(!MessageTimeline.isGrouped(try message(id: 2, time: 2_000, plugin: "plugin"), after: first))
        #expect(!MessageTimeline.isGrouped(try message(id: 2, time: 2_000, reply: 9), after: first))
        #expect(!MessageTimeline.isGrouped(first, after: try message(id: 2, time: 500, reply: 9)))
        #expect(!MessageTimeline.isGrouped(first, after: nil))
    }

    @Test func unreadBoundaryExcludesOwnMessages() throws {
        let messages = try [
            message(id: 1, time: 1_000, userId: 2),
            message(id: 2, time: 2_000),
            message(id: 3, time: 3_000, userId: 2),
            message(id: 4, time: 4_000)
        ]
        #expect(MessageTimeline.firstUnreadId(in: messages, count: 2, ownUserId: 1) == 1)
        #expect(MessageTimeline.firstUnreadId(in: messages, count: 1, ownUserId: 1) == 3)
        #expect(MessageTimeline.firstUnreadId(in: messages, count: 0, ownUserId: 1) == nil)
        #expect(MessageTimeline.firstUnreadId(in: messages, count: 10, ownUserId: 1) == 1)
    }

    @Test @MainActor func clearingUnreadRetainsTheCapturedDivider() throws {
        let session = SharkordSession()
        session.ownUserId = 1
        session.unreadByChannel[7] = 1
        session.messagesByChannel[7] = try [message(id: 3, time: 3_000, userId: 2)]
        session.markAsRead(7)
        #expect(session.unreadByChannel[7] == 0)
        #expect(session.unreadBoundaryByChannel[7] == 3)
        session.messagesByChannel[7]?.insert(try message(id: 1, time: 1_000, userId: 2), at: 0)
        session.markAsRead(7)
        #expect(session.unreadBoundaryByChannel[7] == 3)
        session.disconnect()
        #expect(session.unreadBoundaryByChannel.isEmpty)
    }

    @Test @MainActor func failedPresentReloadKeepsTheReadingWindow() async throws {
        let session = SharkordSession()
        session.messagesByChannel[7] = try [message(id: 3, time: 3_000)]
        session.hasNewerByChannel[7] = true
        await session.returnToPresent(channelId: 7)
        #expect(session.messagesByChannel[7]?.map(\.id) == [3])
        #expect(session.hasNewerByChannel[7] == true)
        #expect(session.lastError != nil)
    }

    @Test @MainActor func duplicateSelectionDoesNotClearUnreadBeforeHistoryArrives() async {
        let session = SharkordSession()
        session.unreadByChannel[7] = 2
        session.isLoadingInitialMessagesByChannel.insert(7)
        await session.select(channelId: 7)
        #expect(session.unreadByChannel[7] == 2)
        #expect(session.lastError == nil)
    }

    private func message(id: Int, time: Int, userId: Int = 1, plugin: String? = nil, reply: Int? = nil) throws -> SharkordMessage {
        var value: [String: JSONValue] = [
            "id": .int(id), "channelId": .int(7), "createdAt": .int(time), "userId": .int(userId)
        ]
        if let plugin { value["pluginId"] = .string(plugin) }
        if let reply { value["replyToMessageId"] = .int(reply) }
        return try JSONValue.object(value).decode(SharkordMessage.self)
    }
}
