import Foundation
import Testing
@testable import SharkordCore

@MainActor
struct ChannelPresentationTests {
    @Test func directMessagesStayTextOnlyWhenTheServerUsesTheVoiceChannelType() throws {
        let decoder = JSONDecoder()
        let directMessage = try decoder.decode(SharkordChannel.self, from: Data("""
        {"id": 1, "type": "VOICE", "name": "DM - 1:2", "private": true, "isDm": true, "position": 0, "createdAt": 0}
        """.utf8))
        let voiceRoom = try decoder.decode(SharkordChannel.self, from: Data("""
        {"id": 2, "type": "VOICE", "name": "Voice", "private": false, "isDm": false, "position": 0, "createdAt": 0}
        """.utf8))

        #expect(!directMessage.isVoiceChannel)
        #expect(voiceRoom.isVoiceChannel)
    }
}
