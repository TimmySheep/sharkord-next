import XCTest
@testable import SharkordMac

final class MessageDeletionConfirmationTests: XCTestCase {
    func testMessageDeleteActionsAreGuardedByLocalizedConfirmation() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/SharkordMac/MessageListView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("L10n.t(\"deleteMessageConfirm\", ns: \"common\")"))
        XCTAssertTrue(source.contains("private func requestDeleteConfirmation()"))
        XCTAssertEqual(source.components(separatedBy: "requestDeleteConfirmation()").count - 1, 3)
        XCTAssertEqual(source.components(separatedBy: "session.deleteMessage(message.id)").count - 1, 1)
    }
}
