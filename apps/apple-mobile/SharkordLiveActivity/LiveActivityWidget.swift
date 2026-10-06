import ActivityKit
import SwiftUI
import WidgetKit

/// the widget extension's entry point. every view here renders the *shape* of a session rather than
/// live data: it reads whatever `LiveActivityAttributes.ContentState` it is handed, and nothing in
/// the app hands it real session state yet.
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
                    VStack(alignment: .trailing, spacing: 1) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("\(context.state.participantCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
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

@main
struct SharkordLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SharkordLiveActivityWidget()
    }
}
