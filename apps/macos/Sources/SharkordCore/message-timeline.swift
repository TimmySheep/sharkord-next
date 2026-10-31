import Foundation

public enum MessageTimeline {
    static func precedes(_ first: SharkordMessage, _ second: SharkordMessage) -> Bool {
        if first.createdAt == second.createdAt { return first.id < second.id }
        return first.createdAt < second.createdAt
    }

    public static func isGrouped(_ message: SharkordMessage, after previous: SharkordMessage?) -> Bool {
        guard let previous else { return false }
        return previous.userId == message.userId
            && previous.pluginId == message.pluginId
            && previous.replyToMessageId == nil
            && message.replyToMessageId == nil
            && abs(message.createdAt - previous.createdAt) < 60_000
    }

    public static func firstUnreadId(in messages: [SharkordMessage], count: Int, ownUserId: Int) -> Int? {
        guard count > 0 else { return nil }
        // the server's unread count excludes the viewer's own messages
        return messages.lazy.filter { $0.userId != ownUserId }.suffix(count).first?.id
    }
}
