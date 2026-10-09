import SharkordCore
import SwiftUI
import UIKit

/// the voice channel picker used by the channel workspace.
struct VoiceTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        if let channelId = voice.currentChannelId {
            VoiceRoomView(channelId: channelId)
        } else {
            picker
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: L10n.t("nav.voice"))

                if let banner = model.banner {
                    bannerView(banner)
                }

                if session.voiceChannels.isEmpty {
                    EmptyStateView(
                        symbol: "waveform",
                        title: L10n.t("voice.emptyRoom"),
                        body_: L10n.t("chat.pickBody")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    SectionLabel(icon: "waveform", text: L10n.t("nav.voiceChannels"))

                    ForEach(session.voiceChannels) { channel in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 13) {
                                Image(systemName: "waveform")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SharkordTheme.textSecondary)
                                    .frame(width: 26)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(channel.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(SharkordTheme.textPrimary)
                                        .lineLimit(1)

                                    if let topic = channel.topic, !topic.isEmpty {
                                        Text(topic)
                                            .font(.footnote)
                                            .foregroundStyle(SharkordTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 8)

                                Text("\(session.voiceParticipants(in: channel.id).count)")
                                    .font(.subheadline)
                                    .foregroundStyle(SharkordTheme.textSecondary)
                            }

                            SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                                model.joinVoice(channel.id)
                            }
                        }
                        .sharkordCard(cornerRadius: 24, padding: 17)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func bannerView(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }
}

struct VoiceChannelPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    let channelId: Int
    let onJoin: () -> Void
    let onOpenChat: () -> Void

    private var participants: [VoiceParticipant] {
        session.voiceParticipants(in: channelId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.channel(for: channelId)?.name ?? "")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SharkordTheme.textPrimary)

                Text(L10n.format("voice.preview.memberCount", participants.count))
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }

            if participants.isEmpty {
                Text(L10n.t("voice.preview.emptyRoom"))
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(participants) { participant in
                            VoicePreviewParticipant(participant: participant)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 12) {
                Button(action: model.toggleMicrophoneEnabledOnJoin) {
                    Image(systemName: model.microphoneEnabledOnJoin ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(model.microphoneEnabledOnJoin ? SharkordTheme.accentSoft : SharkordTheme.danger)
                        .frame(width: 48, height: 48)
                        .background(SharkordTheme.card, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(model.microphoneEnabledOnJoin ? "voice.action.micOff" : "voice.action.micOn"))

                SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill", action: onJoin)
                    .frame(maxWidth: .infinity)

                Button(action: onOpenChat) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(SharkordTheme.card, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("voice.openChat"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandBackground())
    }
}

private struct VoicePreviewParticipant: View {
    let participant: VoiceParticipant

    var body: some View {
        VStack(spacing: 6) {
            SessionAvatarView(user: participant.user, diameter: 56)
            HStack(spacing: 4) {
                if participant.state.micMuted {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(SharkordTheme.danger)
                }
                Text(participant.user.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(SharkordTheme.textPrimary)
        }
        .frame(width: 76)
    }
}

/// the live call uses a participant stage and a fixed control strip, like the Android call screen.
struct VoiceRoomView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let channelId: Int
    @State private var expandedScreenShareID: String?

    var body: some View {
        Group {
            if isInThisCall {
                activeCall
            } else {
                joinPage
            }
        }
    }

    private var joinPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topicHeader
                if let banner = model.banner {
                    bannerView(banner)
                }
                SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                    model.joinVoice(channelId)
                }
                participants
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var activeCall: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                bannerView(banner)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if let topic = session.channel(for: channelId)?.topic, !topic.isEmpty {
                Text(topic)
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if let expandedScreenShare {
                RemoteScreenShareCard(
                    stream: expandedScreenShare,
                    label: session.user(for: expandedScreenShare.remoteId)?.name
                        ?? L10n.t("message.unknownAuthor"),
                    expanded: true,
                    onToggleSize: { expandedScreenShareID = nil }
                )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                participantStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if expandedScreenShare == nil && !unassignedRemoteCameraStreams.isEmpty {
                RemoteStreamList(streams: unassignedRemoteCameraStreams)
                    .frame(maxHeight: 230)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()
            callControls
        }
        .onChange(of: screenShareStreams.map(\.id)) { _, streamIDs in
            guard let expandedScreenShareID, !streamIDs.contains(expandedScreenShareID) else { return }
            self.expandedScreenShareID = nil
        }
    }

    private var topicHeader: some View {
        Group {
            if let topic = session.channel(for: channelId)?.topic, !topic.isEmpty {
                Text(topic)
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isInThisCall: Bool {
        voice.currentChannelId == channelId
    }

    private var participantRows: [VoiceParticipant] {
        session.voiceParticipants(in: channelId)
    }

    private var screenShareStreams: [RemoteVideoStream] {
        voice.remoteVideoStreams.filter { $0.kind == .screen }
    }

    private var remoteCameraStreams: [RemoteVideoStream] {
        voice.remoteVideoStreams.filter { $0.kind == .video }
    }

    private var unassignedRemoteCameraStreams: [RemoteVideoStream] {
        let participantIds = Set(participantRows.map(\.id))
        return remoteCameraStreams.filter { !participantIds.contains($0.remoteId) }
    }

    private var expandedScreenShare: RemoteVideoStream? {
        guard let expandedScreenShareID else { return nil }
        return screenShareStreams.first { $0.id == expandedScreenShareID }
    }

    private var participantStage: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let previewWidth = min(geometry.size.width * (isLandscape ? 0.3 : 0.44), 240)
            let previewHeight = min(geometry.size.height * (isLandscape ? 0.38 : 0.2), 168)

            ZStack(alignment: .bottomTrailing) {
                Group {
                    if participantRows.isEmpty {
                        Text(L10n.t("voice.emptyRoom"))
                            .font(.subheadline)
                            .foregroundStyle(SharkordTheme.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                SharkordTheme.card,
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                            )
                    } else if participantRows.count == 1, let participant = participantRows.first {
                        participantTile(
                            participant,
                            diameter: min(geometry.size.width, geometry.size.height) * 0.34,
                            featured: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(participantRows) { participant in
                                    participantTile(participant)
                                        .aspectRatio(1.15, contentMode: .fit)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                if !screenShareStreams.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(screenShareStreams) { stream in
                                RemoteScreenShareCard(
                                    stream: stream,
                                    label: session.user(for: stream.remoteId)?.name
                                        ?? L10n.t("message.unknownAuthor"),
                                    expanded: false,
                                    onToggleSize: { expandedScreenShareID = stream.id }
                                )
                                .frame(width: previewWidth, height: previewHeight)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: geometry.size.width * 0.82, alignment: .trailing)
                    .frame(height: previewHeight)
                    .padding(12)
                }
            }
        }
        .padding(12)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("channel.currentMembers"))
                    .font(.headline)
                    .foregroundStyle(SharkordTheme.textPrimary)

                Spacer()

                Text("\(participantRows.count)")
                    .font(.body)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }

            if participantRows.isEmpty {
                Text(L10n.t("voice.emptyRoom"))
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: participantColumns, spacing: 12) {
                    ForEach(participantRows) { participant in
                        participantTile(participant)
                    }
                }
            }
        }
    }

    private var participantColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)]
    }

    private func participantTile(
        _ participant: VoiceParticipant,
        diameter: CGFloat = 68,
        featured: Bool = false
    ) -> some View {
        let isSelf = participant.id == session.ownUserId
        let avatarURL = participant.user.avatar.flatMap(session.publicFileURL(for:))
        let remoteCamera = isSelf ? nil : remoteCameraStreams.first { $0.remoteId == participant.id }

        return VoiceParticipantCard(
            avatarURL: avatarURL,
            isSpeaking: voice.activeSpeakerIds.contains(participant.id),
            cornerRadius: featured ? 28 : 16
        ) { _, foreground in
            VStack(spacing: featured ? 18 : 10) {
                if isSelf, voice.cameraOn, let track = voice.localCameraTrack {
                    RemoteVideoView(track: track)
                        .frame(maxWidth: .infinity)
                        .frame(height: featured ? 230 : 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button(action: model.switchCamera) {
                                Image(systemName: "camera.rotate.fill")
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t("voice.camera.switch"))
                            .padding(8)
                        }
                } else if let remoteCamera {
                    RemoteVideoView(track: remoteCamera.track)
                        .frame(maxWidth: .infinity)
                        .frame(height: featured ? 230 : 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            RemoteStreamQualityMenu(stream: remoteCamera)
                                .padding(8)
                        }
                } else {
                    AvatarView(
                        name: participant.user.name,
                        diameter: diameter,
                        imageURL: avatarURL
                    )
                }

                HStack(spacing: 6) {
                    Text(participant.user.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(foreground)
                        .lineLimit(1)

                    if isSelf {
                        Text(L10n.t("voice.youTag"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(foreground.opacity(0.75))
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: participant.state.micMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(participant.state.micMuted ? SharkordTheme.danger : foreground.opacity(0.78))

                    if participant.state.sharingScreen == true {
                        Image(systemName: "rectangle.on.rectangle.fill")
                            .foregroundStyle(foreground)
                            .accessibilityLabel(L10n.t("voice.state.screenSharing"))
                    }

                    Text(stateText(participant.state))
                        .font(.caption)
                        .foregroundStyle(foreground.opacity(0.78))
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: featured ? .infinity : nil)
            .frame(minHeight: featured ? 0 : 144)
            .padding(featured ? 20 : 12)
        }
    }

    private var callControls: some View {
        let cameraAllowed = session.hasPermission(.enableWebcam) &&
            session.hasChannelPermission(channelId, .webcam)

        return HStack(spacing: 4) {
            VoiceRoomControlButton(
                symbol: voice.microphoneOn ? "mic.fill" : "mic.slash.fill",
                accessibilityLabel: L10n.t(voice.microphoneOn ? "voice.action.micOff" : "voice.action.micOn"),
                active: voice.microphoneOn,
                enabled: voice.callState == .connected,
                action: model.toggleMicrophone
            )
            VoiceRoomControlButton(
                symbol: voice.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                accessibilityLabel: L10n.t(voice.deafened ? "voice.action.speakerOn" : "voice.action.speakerOff"),
                active: !voice.deafened,
                action: model.toggleDeafen
            )
            VoiceRoomControlButton(
                symbol: voice.cameraOn ? "video.fill" : "video.slash.fill",
                accessibilityLabel: L10n.t(voice.cameraOn ? "voice.camera.stop" : "voice.camera.start"),
                active: voice.cameraOn,
                enabled: voice.callState == .connected && (cameraAllowed || voice.cameraOn),
                action: model.toggleCamera
            )
            ScreenShareControls(channelId: channelId, compact: true)
                .frame(maxWidth: .infinity)
            VoiceRoomControlButton(
                symbol: "phone.down.fill",
                accessibilityLabel: L10n.t("voice.leave"),
                active: false,
                danger: true,
                action: model.leaveVoice
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(SharkordTheme.background)
    }

    private func bannerView(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }

    private func stateText(_ state: VoiceUserState) -> String {
        if state.sharingScreen == true {
            return L10n.t("voice.state.screenSharing")
        }
        if state.soundMuted {
            return L10n.t("voice.state.deafened")
        }
        if state.micMuted {
            return L10n.t("voice.state.muted")
        }
        return L10n.t("voice.state.live")
    }
}

private struct VoiceRoomControlButton: View {
    let symbol: String
    let accessibilityLabel: String
    let active: Bool
    var enabled = true
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(danger ? SharkordTheme.danger : (active ? SharkordTheme.accentSoft : SharkordTheme.textSecondary))
                .frame(width: 48, height: 48)
                .background(SharkordTheme.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .frame(maxWidth: .infinity)
    }
}

private struct VoiceParticipantCard<Content: View>: View {
    let avatarURL: URL?
    let isSpeaking: Bool
    let cornerRadius: CGFloat
    private let content: (Color, Color) -> Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var backgroundColor = SharkordTheme.card
    @State private var foregroundColor = SharkordTheme.textPrimary

    init(
        avatarURL: URL?,
        isSpeaking: Bool,
        cornerRadius: CGFloat,
        @ViewBuilder content: @escaping (Color, Color) -> Content
    ) {
        self.avatarURL = avatarURL
        self.isSpeaking = isSpeaking
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content(backgroundColor, foregroundColor)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSpeaking ? SharkordTheme.success : .clear, lineWidth: 3)
                    .padding(2)
            }
            .task(id: "\(avatarURL?.absoluteString ?? "")-\(colorScheme == .dark)") {
                backgroundColor = SharkordTheme.card
                foregroundColor = SharkordTheme.textPrimary
                guard let avatarURL,
                      let (data, response) = try? await URLSession.shared.data(from: avatarURL),
                      ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300,
                      !Task.isCancelled,
                      let image = UIImage(data: data)
                else {
                    return
                }

                let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
                let traits = UITraitCollection(userInterfaceStyle: interfaceStyle)
                guard let colors = VoiceParticipantTileColor.colors(for: image, traits: traits) else {
                    return
                }
                backgroundColor = Color(uiColor: colors.background)
                foregroundColor = Color(uiColor: colors.foreground)
            }
    }
}

private enum VoiceParticipantTileColor {
    private static let sampleSize = 24
    private static let minimumContrast = 3.0

    static func colors(
        for image: UIImage,
        traits: UITraitCollection
    ) -> (background: UIColor, foreground: UIColor)? {
        guard let cgImage = image.cgImage,
              let dominantColor = dominantColor(in: cgImage)
        else {
            return nil
        }

        let surfaceColor = UIColor.systemBackground.resolvedColor(with: traits)
        let background = adjustedForContrast(dominantColor, against: surfaceColor, traits: traits)
        let whiteContrast = contrastRatio(.white, background, traits: traits)
        let blackContrast = contrastRatio(.black, background, traits: traits)
        let foreground = whiteContrast >= blackContrast ? UIColor.white : UIColor.black
        return (background, foreground)
    }

    private static func dominantColor(in image: CGImage) -> UIColor? {
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: sampleSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
            return true
        }
        guard didDraw else { return nil }

        var buckets: [Int: ColorBucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            guard pixels[offset + 3] >= 128 else { continue }
            let key = ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3)
            var bucket = buckets[key] ?? ColorBucket()
            bucket.add(red: red, green: green, blue: blue)
            buckets[key] = bucket
        }

        guard let dominant = buckets.values.max(by: { $0.count < $1.count }), dominant.count > 0 else {
            return nil
        }
        return UIColor(
            red: CGFloat(dominant.redTotal / dominant.count) / 255,
            green: CGFloat(dominant.greenTotal / dominant.count) / 255,
            blue: CGFloat(dominant.blueTotal / dominant.count) / 255,
            alpha: 1
        )
    }

    private static func adjustedForContrast(
        _ color: UIColor,
        against surface: UIColor,
        traits: UITraitCollection
    ) -> UIColor {
        guard contrastRatio(color, surface, traits: traits) < minimumContrast else { return color }

        var candidates: [(color: UIColor, amount: Double)] = []
        for target in [UIColor.white, UIColor.black] {
            guard contrastRatio(target, surface, traits: traits) >= minimumContrast else { continue }
            var low = 0.0
            var high = 1.0
            for _ in 0..<16 {
                let middle = (low + high) / 2
                let blended = blend(color, toward: target, amount: middle, traits: traits)
                if contrastRatio(blended, surface, traits: traits) >= minimumContrast {
                    high = middle
                } else {
                    low = middle
                }
            }
            candidates.append((blend(color, toward: target, amount: high, traits: traits), high))
        }

        return candidates.min(by: { $0.amount < $1.amount })?.color ?? color
    }

    private static func blend(
        _ color: UIColor,
        toward target: UIColor,
        amount: Double,
        traits: UITraitCollection
    ) -> UIColor {
        guard let first = components(of: color, traits: traits),
              let second = components(of: target, traits: traits)
        else {
            return color
        }
        let inverse = 1 - amount
        return UIColor(
            red: first.red * inverse + second.red * amount,
            green: first.green * inverse + second.green * amount,
            blue: first.blue * inverse + second.blue * amount,
            alpha: 1
        )
    }

    private static func contrastRatio(_ first: UIColor, _ second: UIColor, traits: UITraitCollection) -> Double {
        guard let first = components(of: first, traits: traits),
              let second = components(of: second, traits: traits)
        else {
            return 1
        }
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) /
            (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func components(
        of color: UIColor,
        traits: UITraitCollection
    ) -> (red: Double, green: Double, blue: Double)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return nil
        }
        return (Double(red), Double(green), Double(blue))
    }

    private static func luminance(_ color: (red: Double, green: Double, blue: Double)) -> Double {
        linear(color.red) * 0.2126 + linear(color.green) * 0.7152 + linear(color.blue) * 0.0722
    }

    private static func linear(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    private struct ColorBucket {
        var count = 0
        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0

        mutating func add(red: Int, green: Int, blue: Int) {
            count += 1
            redTotal += red
            greenTotal += green
            blueTotal += blue
        }
    }
}

/// incoming camera streams, labelled by owner and kind.
struct RemoteStreamList: View {
    @EnvironmentObject private var session: SharkordSession

    let streams: [RemoteVideoStream]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(
                icon: "rectangle.on.rectangle.fill",
                text: L10n.t("voice.remoteStreams"),
                tint: SharkordTheme.accentSoft
            )

            ForEach(streams) { stream in
                RemoteVideoView(track: stream.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text(streamLabel(stream))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        RemoteStreamQualityMenu(stream: stream)
                            .padding(10)
                    }
            }
        }
        .sharkordCard(cornerRadius: 24)
    }

    private func streamLabel(_ stream: RemoteVideoStream) -> String {
        let name = session.user(for: stream.remoteId)?.name ?? L10n.t("message.unknownAuthor")
        let kind = stream.kind == .screen || stream.kind == .screenAudio
            ? L10n.t("voice.screen.start")
            : L10n.t("voice.remoteCamera")
        return "\(name) · \(kind)"
    }
}

private struct RemoteScreenShareCard: View {
    let stream: RemoteVideoStream
    let label: String
    let expanded: Bool
    let onToggleSize: () -> Void

    var body: some View {
        ZStack {
            Color.black
            RemoteVideoView(track: stream.track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                RemoteStreamQualityMenu(stream: stream)

                Button(action: onToggleSize) {
                    Image(systemName: expanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(expanded ? "voice.screen.minimize" : "voice.screen.maximize"))
            }
            .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RemoteStreamQualityMenu: View {
    @EnvironmentObject private var voice: VoiceEngine

    let stream: RemoteVideoStream

    var body: some View {
        if !stream.qualityLayers.isEmpty {
            Menu {
                Button(L10n.t("voice.quality.auto")) {
                    Task { await voice.setQuality(for: stream, spatialLayer: nil) }
                }
                ForEach(stream.qualityLayers, id: \.spatialLayer) { layer in
                    Button(layer.label) {
                        Task { await voice.setQuality(for: stream, spatialLayer: layer.spatialLayer) }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
    }
}
