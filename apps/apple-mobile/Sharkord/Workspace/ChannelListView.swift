import SwiftUI

/// categories and channels. selection is passed in rather than owned here so the same list can drive a
/// push stack on iPhone and a split view detail on iPad.
struct ChannelListView: View {
    @ObservedObject var model: AppModel
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                serverHeader
                OfflineNotice()

                ForEach(model.categories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(title: category.name)
                            .padding(.horizontal, 4)

                        VStack(spacing: 4) {
                            ForEach(category.channels) { channel in
                                channelRow(channel)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(model.serverDisplayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var serverHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Color.sharkordBlue,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.serverDisplayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("已登录为 \(model.accountDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 4)
    }

    private func channelRow(_ channel: ServerChannel) -> some View {
        let isSelected = selectedID == channel.id

        return Button {
            onSelect(channel.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: channel.kind == .text ? "number" : "speaker.wave.2")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? Color.sharkordBlue : Color.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if channel.kind == .voice {
                        Text(voiceCaption(channel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sharkordBlue)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.sharkordBlue.opacity(0.11))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func voiceCaption(_ channel: ServerChannel) -> String {
        if channel.voiceMemberIDs.isEmpty {
            return "空闲"
        }
        return "\(channel.voiceMemberIDs.count) 人在频道"
    }
}
