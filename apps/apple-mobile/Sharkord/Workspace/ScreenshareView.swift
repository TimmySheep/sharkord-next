import SharkordCore
import SwiftUI

/// screen sharing controls embedded in a voice channel.
struct ScreenShareControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let channelId: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeading(
                icon: "dot.radiowaves.left.and.right",
                text: L10n.t("screenshare.infoTitle"),
                tint: SharkordTheme.success
            )

            Text(L10n.t("screenshare.infoBody"))
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SharkordPrimaryButton(
                title: isSharingHere ? L10n.t("voice.screen.stop") : L10n.t("voice.screen.start"),
                symbol: isSharingHere ? "rectangle.slash.fill" : "rectangle.on.rectangle.fill",
                enabled: voice.currentChannelId == channelId && (isSharingHere || canShare),
                tint: isSharingHere ? SharkordTheme.danger : SharkordTheme.accent
            ) {
                model.toggleScreenShare()
            }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sharkordCard(cornerRadius: 24)
    }

    private var isSharingHere: Bool {
        voice.currentChannelId == channelId && voice.screenSharing
    }

    private var hint: String {
        if voice.currentChannelId != channelId {
            return L10n.t("voice.error.notInCall")
        }
        return canShare ? L10n.t("screenshare.startHint") : L10n.t("voice.error.screenShareNotAllowed")
    }

    private var canShare: Bool {
        session.hasPermission(.shareScreen) && session.hasChannelPermission(channelId, .shareScreen)
    }
}
