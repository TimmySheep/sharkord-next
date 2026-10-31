import ActivityKit
import SwiftUI
import WidgetKit

/// renders the active voice session in the Dynamic Island and on the lock screen.
struct SharkordLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            ChannelLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "number")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Color.sharkordBlue,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                            Text("\(context.state.participantCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityElement(children: .combine)

                        MicrophoneToggleLink(isMicrophoneOn: context.state.isSpeaking)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.channelName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.topic)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            } compactLeading: {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Color.sharkordBlue,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            } compactTrailing: {
                Text("\(context.state.participantCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.sharkordBlue, in: Capsule())
            } minimal: {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Color.sharkordBlue,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .keylineTint(Color.sharkordBlue)
        }
    }
}

private struct ChannelLiveActivityView: View {
    let context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.sharkordBlue, Color.sharkordBlue.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            .white.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )

                    Text(context.state.channelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(context.state.participantCount) 人")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())

                    MicrophoneToggleLink(isMicrophoneOn: context.state.isSpeaking)
                }

                Text(context.state.topic)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if context.attributes.serverAddress.isEmpty {
                    Text("骨架阶段 · 尚未接入会话")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(14)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
    }
}

private struct MicrophoneToggleLink: View {
    let isMicrophoneOn: Bool

    var body: some View {
        Link(destination: URL(string: "cove://voice/toggle-microphone")!) {
            Image(systemName: isMicrophoneOn ? "mic.fill" : "mic.slash.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.2), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(LocalizedStringKey(isMicrophoneOn ? "liveActivity.muteMicrophone" : "liveActivity.unmuteMicrophone"))
        )
    }
}

@main
struct SharkordLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SharkordLiveActivityWidget()
    }
}
