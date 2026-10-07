import SharkordCore
import SwiftUI
import WatchKit

private struct WatchVoiceParticipant: Identifiable {
    let id: Int
    let name: String
    let micMuted: Bool
}

/// the radio room has an explicit join, hold-to-talk and leave lifecycle.
struct WatchRoomView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var radio: WatchRadioSession
    @Environment(\.dismiss) private var dismiss

    let channelId: Int

    private var channel: SharkordChannel? {
        session.channel(for: channelId)
    }

    private var participants: [WatchVoiceParticipant] {
        session.voiceUsers(in: channelId).map { entry in
            WatchVoiceParticipant(
                id: entry.user.id,
                name: entry.user.name,
                micMuted: entry.state.micMuted
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                participantList
                HoldToTalkButton()
                leaveButton
            }
            .padding(.horizontal, 6)
        }
        .task {
            await radio.join(channelId: channelId)
        }
        .onDisappear {
            Task {
                await radio.leave()
            }
        }
        .digitalCrownRotation($radio.volume, from: 0, through: 1, by: 0.05)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(channel?.name ?? "#\(channelId)")
                .font(.headline)
                .lineLimit(1)
            WatchStatePill(color: stateColor, text: stateText)
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                Text(L10n.format("watch.volume", Int(radio.volume * 100)))
            }
            .font(.caption2)
            .foregroundStyle(WatchTheme.textSecondary)
            Text(L10n.t("watch.volumeHint"))
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary.opacity(0.7))
        }
    }

    private var participantList: some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 6) {
                if participants.isEmpty {
                    Text(L10n.t("voice.emptyRoom"))
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                } else {
                    ForEach(participants) { participant in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(participant.micMuted ? WatchTheme.textSecondary.opacity(0.4) : WatchTheme.accentSoft)
                                .frame(width: 7, height: 7)
                            Text(participant.name)
                                .font(.caption)
                                .foregroundStyle(WatchTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if participant.micMuted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.danger)
                            }
                        }
                    }
                }
            }
        }
    }

    private var leaveButton: some View {
        Button(role: .destructive) {
            Task {
                await radio.leave()
                dismiss()
            }
        } label: {
            Text(L10n.t("watch.leaveChannel"))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .tint(WatchTheme.danger)
    }

    private var stateColor: Color {
        switch radio.state {
        case .joining, .leaving:
            return WatchTheme.accentSoft
        case .listening:
            return .green
        case .transmitting:
            return .red
        case .idle:
            return WatchTheme.textSecondary
        case .failed:
            return WatchTheme.danger
        }
    }

    private var stateText: String {
        switch radio.state {
        case .joining:
            return L10n.t("watch.joining")
        case .listening:
            return L10n.t("watch.listening")
        case .transmitting:
            return L10n.t("watch.transmitting")
        case .leaving:
            return L10n.t("watch.leaveChannel")
        case .idle:
            return L10n.t("watch.joining")
        case .failed(let message):
            return message
        }
    }
}

/// the microphone opens only after the radio session is joined.
private struct HoldToTalkButton: View {
    @EnvironmentObject private var radio: WatchRadioSession
    @State private var isPressed = false

    private var isEnabled: Bool {
        radio.state == .listening || radio.state == .transmitting
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isPressed ? WatchTheme.danger : WatchTheme.accent)
                    .frame(width: 88, height: 88)
                Image(systemName: isPressed ? "waveform" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if isPressed {
                levelMeter
            }

            Text(isPressed ? L10n.t("watch.transmitting") : L10n.t("watch.holdToTalk"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isPressed ? WatchTheme.danger : WatchTheme.accentSoft)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isPressed else {
                        return
                    }
                    isPressed = true
                    Task {
                        await radio.beginTransmit()
                    }
                    WKInterfaceDevice.current().play(.start)
                }
                .onEnded { _ in
                    guard isPressed else {
                        return
                    }
                    isPressed = false
                    Task {
                        await radio.endTransmit()
                    }
                    WKInterfaceDevice.current().play(.stop)
                }
        )
    }

    private var levelMeter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WatchTheme.field)
                Capsule()
                    .fill(WatchTheme.accentSoft)
                    .frame(width: proxy.size.width * CGFloat(min(radio.microphoneLevel * 4, 1)))
            }
        }
        .frame(width: 100, height: 6)
    }
}
