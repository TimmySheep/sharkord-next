import SharkordCore
import SwiftUI

/// The screen share tab: how sharing works, the one button that starts and stops it, the
/// state of this device's own share, and every incoming stream.
struct ScreenshareView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: L10n.t("nav.screenshare"))

                infoCard

                actionCard

                if voice.screenSharing {
                    ownShareCard
                }

                if !voice.remoteVideoStreams.isEmpty {
                    RemoteStreamList()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var infoCard: some View {
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
        }
        .sharkordCard(cornerRadius: 24)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SharkordPrimaryButton(
                title: voice.screenSharing ? L10n.t("voice.screen.stop") : L10n.t("voice.screen.start"),
                symbol: voice.screenSharing ? "rectangle.slash.fill" : "rectangle.on.rectangle.fill",
                enabled: voice.currentChannelId != nil,
                tint: voice.screenSharing ? SharkordTheme.danger : SharkordTheme.accent
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

    private var hint: String {
        voice.currentChannelId == nil
            ? L10n.t("voice.error.notInCall")
            : L10n.t("screenshare.startHint")
    }

    private var ownShareCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(symbol: "rectangle.on.rectangle.fill", tint: SharkordTheme.accentSoft)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("screenshare.myScreen"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)

                    Text(L10n.t("voice.state.screenSharing"))
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.textSecondary)
                }

                Spacer(minLength: 8)
            }

            SharkordSecondaryButton(
                title: L10n.t("voice.screen.stop"),
                symbol: "stop.fill",
                tint: SharkordTheme.danger,
                background: SharkordTheme.dangerDeep
            ) {
                model.toggleScreenShare()
            }
        }
        .sharkordCard(cornerRadius: 24)
    }
}
