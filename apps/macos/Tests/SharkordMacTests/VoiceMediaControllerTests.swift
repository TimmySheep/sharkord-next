import XCTest
@testable import SharkordMac

@MainActor
final class VoiceMediaControllerTests: XCTestCase {
    func testPresentingAMediaActionErrorDoesNotChangeConnectionStatus() {
        let controller = VoiceMediaController()

        controller.presentError("The microphone is unavailable.")

        XCTAssertEqual(controller.status, "idle")
        XCTAssertEqual(controller.errorMessage, "The microphone is unavailable.")
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
