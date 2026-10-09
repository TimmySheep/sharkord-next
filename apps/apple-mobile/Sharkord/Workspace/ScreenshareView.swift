import SharkordCore
import SwiftUI

/// screen sharing controls embedded in a voice channel.
struct ScreenShareControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let channelId: Int
    @State private var isBroadcastPickerPresented = false

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

            if isSharingHere {
                SharkordPrimaryButton(
                    title: L10n.t("voice.screen.stop"),
                    symbol: "rectangle.slash.fill",
                    tint: SharkordTheme.danger
                ) {
                    model.toggleScreenShare()
                }
            } else if voice.screenShareStarting {
                Label(L10n.t("screenshare.waitingForBroadcast"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                SharkordPrimaryButton(
                    title: L10n.t("voice.screen.start"),
                    symbol: "rectangle.on.rectangle.fill",
                    enabled: voice.currentChannelId == channelId && canShare
                ) {
                    model.prepareScreenShare()
                    if voice.screenShareStarting {
                        isBroadcastPickerPresented = true
                    }
                }
            }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sharkordCard(cornerRadius: 24)
        .sheet(isPresented: $isBroadcastPickerPresented) {
            broadcastPickerSheet
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(voice.screenShareStarting)
        }
        .onChange(of: voice.screenSharing) { _, isSharing in
            if isSharing {
                isBroadcastPickerPresented = false
            }
        }
    }

    private var broadcastPickerSheet: some View {
        VStack(spacing: 16) {
            Text(L10n.t("screenshare.broadcastTitle"))
                .font(.headline)
                .foregroundStyle(SharkordTheme.textPrimary)
            Text(L10n.t("screenshare.broadcastBody"))
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ScreenBroadcastPicker()
                .frame(width: 220, height: 48)
            Button(L10n.t("common.cancel")) {
                voice.cancelScreenBroadcastPreparation()
                isBroadcastPickerPresented = false
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
    }

    private var isSharingHere: Bool {
        voice.currentChannelId == channelId && voice.screenSharing
    }

    private var hint: String {
        if voice.currentChannelId != channelId {
            return L10n.t("voice.error.notInCall")
        }
        if !canShare {
            return L10n.t("voice.error.screenShareNotAllowed")
        }
        if voice.screenSharing {
            return L10n.t("screenshare.stopHint")
        }
        return L10n.t("screenshare.startHint")
    }

    private var canShare: Bool {
        session.hasPermission(.shareScreen) && session.hasChannelPermission(channelId, .shareScreen)
    }
}
