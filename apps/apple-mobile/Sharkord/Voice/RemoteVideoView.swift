import SharkordCore
import SwiftUI
import WebRTC

/// A remote video or screen track that is being received.
struct RemoteVideoStream: Identifiable {
    let id: String
    let remoteId: Int
    let kind: StreamKind
    let track: RTCVideoTrack
    let qualityLayers: [StreamQualityLayer]
}

/// Renders one remote WebRTC video track (camera or screen share).
struct RemoteVideoView: UIViewRepresentable {
    final class Coordinator {
        private(set) var track: RTCVideoTrack

        init(track: RTCVideoTrack) {
            self.track = track
        }

        func update(track: RTCVideoTrack, view: RTCMTLVideoView) {
            guard self.track !== track else { return }

            self.track.remove(view)
            self.track = track
            track.add(view)
        }
    }

    let track: RTCVideoTrack

    func makeCoordinator() -> Coordinator {
        Coordinator(track: track)
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        track.add(view)
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.update(track: track, view: uiView)
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track.remove(uiView)
    }
}
