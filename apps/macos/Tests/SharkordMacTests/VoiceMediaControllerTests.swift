import XCTest
import WebKit
@testable import SharkordMac

@MainActor
final class VoiceMediaControllerTests: XCTestCase {
    func testPresentingAMediaActionErrorDoesNotChangeConnectionStatus() {
        let controller = VoiceMediaController()

        controller.presentError("The microphone is unavailable.")

        XCTAssertEqual(controller.status, "idle")
        XCTAssertEqual(controller.errorMessage, "The microphone is unavailable.")
    }

    /// A plain WKWebView user agent has no "Safari" token, so mediasoup-client's
    /// detectDevice reports "device not supported" and voice never connects.
    func testMediaWorkerUserAgentIsRecognisedAsSafari() async throws {
        let view = WKWebView(frame: .zero, configuration: VoiceMediaController.makeConfiguration())

        let value = try await view.callAsyncJavaScript(
            "return navigator.userAgent",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let userAgent = try XCTUnwrap(value as? String)

        // the exact rules mediasoup-client's detectDevice applies to choose the Safari handler
        XCTAssertNotNil(userAgent.range(of: "\\bSafari\\b", options: .regularExpression))
        XCTAssertNil(userAgent.range(of: "Chrome|Chromium|Firefox", options: .regularExpression))

        let match = try XCTUnwrap(userAgent.range(of: "AppleWebKit/(\\d+)", options: .regularExpression))
        let major = Int(userAgent[match].replacingOccurrences(of: "AppleWebKit/", with: ""))

        XCTAssertNotNil(major)
        XCTAssertGreaterThanOrEqual(major ?? 0, 605)
    }

    func testMediaCapturePermissionOnlyGrantsTheBundledLocalPage() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/VoiceMediaController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("view.uiDelegate = self"))
        XCTAssertTrue(source.contains("origin.protocol == \"file\" ? .grant : .deny"))
    }
}
