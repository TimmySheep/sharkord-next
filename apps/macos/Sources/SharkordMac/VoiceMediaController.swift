import Combine
import Foundation
import SharkordCore
import SwiftUI
import WebKit

@MainActor
final class VoiceMediaController: NSObject, ObservableObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    @Published private(set) var status = "idle"
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorContext: String?
    @Published private(set) var canPublishAudio = false
    @Published private(set) var remoteAudioVolumes = VoiceAudioVolumeSettings.load()

    private weak var session: SharkordSession?
    private var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    private var currentChannelId: Int?
    private var knownProducerKeys = Set<String>()
    private var ready = false
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []
    private var previousRemoteAudioVolumes: [String: Double] = [:]

    func bind(to session: SharkordSession) {
        guard self.session !== session else {
            return
        }

        self.session = session
        cancellables.removeAll()

        session.$producersByChannel
            .sink { [weak self] _ in self?.syncProducers() }
            .store(in: &cancellables)

        session.$voiceMap
            .sink { [weak self] _ in
                guard let self, let currentChannelId = self.currentChannelId else {
                    return
                }

                if session.currentVoiceChannelId != currentChannelId {
                    self.stop()
                }
            }
            .store(in: &cancellables)

        session.$phase
            .sink { [weak self] phase in
                if phase != .connected {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
    }

    func makeWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let contentController = WKUserContentController()
        contentController.add(self, name: "coveVoice")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.uiDelegate = self
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        self.webView = view

        if let page = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "voice-media") {
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            errorMessage = "The voice media engine could not be loaded."
        }

        return view
    }

    func start(
        channelId: Int,
        routerRtpCapabilities: JSONValue,
        canProduceAudio: Bool,
        canShareScreen: Bool,
        screenShareLabels: [String: String]
    ) async throws {
        guard let session else {
            throw TRPCClientError(code: "DISCONNECTED", message: "The server session is not available.")
        }

        guard session.currentVoiceChannelId == channelId else {
            throw TRPCClientError(code: "BAD_REQUEST", message: "Join the voice channel before starting media.")
        }

        currentChannelId = channelId
        knownProducerKeys.removeAll()
        errorMessage = nil
        errorContext = nil
        status = "connecting"
        await waitUntilReady()

        guard let webView else {
            throw TRPCClientError(code: "INTERNAL_SERVER_ERROR", message: "The voice media engine is unavailable.")
        }

        try await applyRemoteAudioVolumes(to: webView)

        let capabilitiesData = try JSONEncoder().encode(routerRtpCapabilities)
        let capabilities = try JSONSerialization.jsonObject(with: capabilitiesData, options: [.fragmentsAllowed])
        _ = try await webView.callAsyncJavaScript(
            "return await window.coveVoice.start(channelId, capabilities, canProduceAudio, canShareScreen, screenShareLabels)",
            arguments: [
                "channelId": channelId,
                "capabilities": capabilities,
                "canProduceAudio": canProduceAudio,
                "canShareScreen": canShareScreen,
                "screenShareLabels": screenShareLabels
            ],
            in: nil,
            contentWorld: .page
        )
        syncProducers()
    }

    func setMicrophoneMuted(_ muted: Bool) async throws {
        guard let webView else {
            throw TRPCClientError(code: "DISCONNECTED", message: "The voice media engine is unavailable.")
        }

        _ = try await webView.callAsyncJavaScript(
            "return await window.coveVoice.setMicrophoneMuted(muted)",
            arguments: ["muted": muted],
            in: nil,
            contentWorld: .page
        )
    }

    func presentError(_ message: String, context: String? = nil) {
        errorMessage = message
        errorContext = context
        ClientLogStore.shared.recordFailure("voice.media.failed", code: context ?? "unknown")
    }

    func presentError(_ error: Error, context: String? = nil) {
        ClientLogStore.shared.recordError("voice.\(context ?? "media").failed", error: error)
        errorMessage = error.localizedDescription
        errorContext = context
    }

    func setOutputMuted(_ muted: Bool) async throws {
        guard let webView else {
            throw TRPCClientError(code: "DISCONNECTED", message: "The voice media engine is unavailable.")
        }

        _ = try await webView.callAsyncJavaScript(
            "return await window.coveVoice.setOutputMuted(muted)",
            arguments: ["muted": muted],
            in: nil,
            contentWorld: .page
        )
    }

    func remoteAudioVolume(for userId: Int, stream: VoiceAudioStream) -> Double {
        VoiceAudioVolumeSettings.volume(
            userId: userId,
            stream: stream,
            in: remoteAudioVolumes
        )
    }

    func setRemoteAudioVolume(_ volume: Double, for userId: Int, stream: VoiceAudioStream) {
        guard userId > 0 else {
            return
        }

        let key = VoiceAudioVolumeSettings.key(userId: userId, stream: stream)
        let normalized = VoiceAudioVolumeSettings.clamped(volume)
        var updated = remoteAudioVolumes
        updated[key] = normalized
        remoteAudioVolumes = updated
        VoiceAudioVolumeSettings.save(updated)

        if normalized > 0 {
            previousRemoteAudioVolumes[key] = normalized
        }

        guard let webView, currentChannelId != nil else {
            return
        }

        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.coveVoice?.setRemoteAudioVolume(userId, kind, volume)",
                    arguments: [
                        "userId": userId,
                        "kind": stream.rawValue,
                        "volume": normalized
                    ],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                presentError(error)
            }
        }
    }

    func toggleRemoteAudioMute(for userId: Int, stream: VoiceAudioStream) {
        let key = VoiceAudioVolumeSettings.key(userId: userId, stream: stream)
        let current = remoteAudioVolume(for: userId, stream: stream)

        if current > 0 {
            previousRemoteAudioVolumes[key] = current
            setRemoteAudioVolume(0, for: userId, stream: stream)
        } else {
            setRemoteAudioVolume(
                previousRemoteAudioVolumes[key] ?? VoiceAudioVolumeSettings.defaultVolume,
                for: userId,
                stream: stream
            )
        }
    }

    func setWebcamEnabled(_ enabled: Bool) async throws {
        guard let webView else {
            throw TRPCClientError(code: "DISCONNECTED", message: "The voice media engine is unavailable.")
        }

        _ = try await webView.callAsyncJavaScript(
            "return await window.coveVoice.setWebcamEnabled(enabled)",
            arguments: ["enabled": enabled],
            in: nil,
            contentWorld: .page
        )
    }

    func stop() {
        currentChannelId = nil
        knownProducerKeys.removeAll()
        errorMessage = nil
        errorContext = nil
        status = "idle"
        canPublishAudio = false

        guard let webView else {
            return
        }

        Task {
            _ = try? await webView.callAsyncJavaScript(
                "window.coveVoice?.stop()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            message.frameInfo.isMainFrame,
            message.frameInfo.securityOrigin.protocol == "file",
            let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else {
            return
        }

        if type == "status" {
            status = body["state"] as? String ?? "idle"
            let nextErrorMessage = body["error"] as? String
            if let nextErrorMessage, !nextErrorMessage.isEmpty, nextErrorMessage != errorMessage {
                ClientLogStore.shared.recordFailure("voice.media_worker.failed", code: "media_worker")
            }
            errorMessage = nextErrorMessage
            errorContext = body["errorContext"] as? String
            canPublishAudio = body["canPublishAudio"] as? Bool ?? false
            return
        }

        if type == "ready" {
            ready = true
            readyContinuations.forEach { $0.resume() }
            readyContinuations.removeAll()
            return
        }

        guard
            type == "rpc",
            let id = body["id"] as? String,
            let path = body["path"] as? String,
            let session
        else {
            return
        }

        let input: JSONValue?
        if let inputObject = body["input"], let data = try? JSONSerialization.data(withJSONObject: inputObject, options: [.fragmentsAllowed]) {
            input = try? JSONDecoder().decode(JSONValue.self, from: data)
        } else {
            input = nil
        }

        Task {
            do {
                let result = try await session.callVoiceMediaProcedure(path, input: input)
                await reply(to: id, result: result, error: nil)
            } catch {
                ClientLogStore.shared.recordError("voice.procedure.failed", error: error)
                await reply(to: id, result: nil, error: error.localizedDescription)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(origin.protocol == "file" ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        readyContinuations.forEach { $0.resume() }
        readyContinuations.removeAll()
    }

    private func waitUntilReady() async {
        if ready {
            return
        }

        await withCheckedContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    private func applyRemoteAudioVolumes(to webView: WKWebView) async throws {
        for entry in VoiceAudioVolumeSettings.entries(in: remoteAudioVolumes) {
            _ = try await webView.callAsyncJavaScript(
                "window.coveVoice?.setRemoteAudioVolume(userId, kind, volume)",
                arguments: [
                    "userId": entry.userId,
                    "kind": entry.stream.rawValue,
                    "volume": entry.volume
                ],
                in: nil,
                contentWorld: .page
            )
        }
    }

    private func reply(to id: String, result: JSONValue?, error: String?) async {
        guard let webView else {
            return
        }

        var response: [String: Any] = ["id": id]

        if let result,
           let data = try? JSONEncoder().encode(result),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            response["result"] = object
        }

        if let error {
            response["error"] = error
        }

        guard
            let responseData = try? JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed, .sortedKeys]),
            let responseJSON = String(data: responseData, encoding: .utf8)
        else {
            return
        }

        _ = try? await webView.evaluateJavaScript("window.coveVoiceResolve(\(responseJSON))")
    }

    private func syncProducers() {
        guard
            let currentChannelId,
            let session,
            let webView
        else {
            return
        }

        let events = session.producersByChannel[currentChannelId] ?? []
        let nextKeys = Set(events.map { "\($0.remoteId):\($0.kind.rawValue)" })

        for key in knownProducerKeys.subtracting(nextKeys) {
            sendProducerChange(key, added: false, to: webView)
        }

        for key in nextKeys.subtracting(knownProducerKeys) where !key.hasPrefix("\(session.ownUserId):") {
            sendProducerChange(key, added: true, to: webView)
        }

        knownProducerKeys = nextKeys
    }

    private func sendProducerChange(_ key: String, added: Bool, to webView: WKWebView) {
        let parts = key.split(separator: ":", maxSplits: 1)

        guard parts.count == 2, let remoteId = Int(parts[0]) else {
            return
        }

        let kind = String(parts[1])
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "window.coveVoiceProducerChange(remoteId, kind, added)",
                arguments: ["remoteId": remoteId, "kind": kind, "added": added],
                in: nil,
                contentWorld: .page
            )
        }
    }
}

struct VoiceMediaHost: NSViewRepresentable {
    @ObservedObject var controller: VoiceMediaController

    func makeNSView(context: Context) -> WKWebView {
        controller.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
