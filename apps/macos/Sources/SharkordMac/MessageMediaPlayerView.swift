import AVKit
import SwiftUI

struct MessageMediaPlayerView: View {
    let media: MessageMediaReference

    @State private var player: AVPlayer

    init(media: MessageMediaReference) {
        self.media = media
        _player = State(initialValue: AVPlayer(url: media.url))
    }

    var body: some View {
        Group {
            if media.type == .video {
                VideoPlayer(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                audioControls
            }
        }
        .onDisappear {
            player.pause()
        }
    }

    private var audioControls: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 8) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(isPlaying ? "pauseAudio" : "playAudio", ns: "macos"))

                Slider(value: progress, in: 0...duration)
                    .accessibilityLabel(L10n.t("audioProgress", ns: "macos"))

                Text("\(timeLabel(currentTime)) / \(timeLabel(duration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(8)
            .frame(maxWidth: 360)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    private var duration: Double {
        let seconds = player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? max(seconds, 1) : 1
    }

    private var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? min(max(seconds, 0), duration) : 0
    }

    private var progress: Binding<Double> {
        Binding(
            get: { currentTime },
            set: { seconds in
                player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            }
        )
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let wholeSeconds = Int(seconds)
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}
