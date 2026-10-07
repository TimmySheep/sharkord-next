import Foundation

/// The watch's app state: a mock server session plus the radio session. Phase 1 is
/// offline by design (the skeleton demonstrates the join / hold to talk / leave flow),
/// phase 2 swaps `connect` for the real Sharkord session and `MockRadioTransport` for
/// the server relay transport.
@MainActor
final class WatchSessionModel: ObservableObject {
    enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
    }

    @Published var phase: Phase = .disconnected
    @Published var errorMessage: String?
    @Published var identity = ""
    @Published var server = ""

    let channels = MockData.channels
    let radio = WatchRadioSession()

    func connect() async {
        phase = .connecting
        errorMessage = nil

        // offline skeleton: pretend to reach the server, then enter the workspace
        try? await Task.sleep(nanoseconds: 600_000_000)
        phase = .connected
    }

    func disconnect() {
        Task {
            await radio.leave()
        }
        phase = .disconnected
    }
}
