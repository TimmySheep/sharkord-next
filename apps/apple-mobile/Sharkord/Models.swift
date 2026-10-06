import Foundation
import SharkordCore

/// App local view models. Server state itself is typed in `SharkordCore`; anything the
/// screens need on top of it lives here.

/// One participant row in a voice channel, carrying the user plus the four state flags
/// the server broadcasts (`micMuted`, `soundMuted`, `webcamEnabled`, `sharingScreen`).
struct VoiceParticipant: Identifiable {
    let user: SharkordUser
    let state: VoiceUserState

    var id: Int { user.id }
}

extension SharkordSession {
    func voiceParticipants(in channelId: Int) -> [VoiceParticipant] {
        voiceUsers(in: channelId).map { VoiceParticipant(user: $0.user, state: $0.state) }
    }
}
