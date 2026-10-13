import Foundation
import Testing
@testable import SharkordCore

@MainActor
struct TypingPresenceTests {
    @Test func typingIsScopedAndExpires() throws {
        let session = SharkordSession()
        session.ownUserId = 1
        session.users = try JSONDecoder().decode([SharkordUser].self, from: Data("""
        [{"id":1,"name":"self","profileColor":"#000000","banned":false,"createdAt":0},
         {"id":2,"name":"other","profileColor":"#000000","banned":false,"createdAt":0}]
        """.utf8))
        let date = Date(timeIntervalSince1970: 100)
        session.recordTyping(TypingEvent(channelId: 7, userId: 2, parentMessageId: 10), at: date)
        session.recordTyping(TypingEvent(channelId: 7, userId: 1, parentMessageId: nil), at: date)
        #expect(session.typingUsers(in: 7, now: date).isEmpty)
        #expect(session.typingUsers(in: 7, parentMessageId: 10, now: date).map(\.id) == [2])
        #expect(session.typingUsers(in: 7, parentMessageId: 10, now: date.addingTimeInterval(6)).isEmpty)
        #expect(session.typingUsers(in: 7, parentMessageId: 10, now: date.addingTimeInterval(-1)).isEmpty)
    }
}
