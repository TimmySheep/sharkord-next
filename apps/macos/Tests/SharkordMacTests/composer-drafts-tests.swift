import XCTest
@testable import SharkordMac

@MainActor
final class ComposerDraftsTests: XCTestCase {
    func testLateSendAndRemovalDoNotReplaceNewDraftText() {
        let drafts = ComposerDrafts()
        let attachment = PendingAttachment(id: "temp", fileId: "temp", fileName: "file.txt")
        drafts.save(text: "new draft", attachments: [attachment], channelId: 7, parentMessageId: 8)
        drafts.clearIfMatches(text: "sent draft", attachments: [attachment], channelId: 7, parentMessageId: 8)
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: 8)?.text, "new draft")
        drafts.removeAttachment(id: "temp", channelId: 7, parentMessageId: 8)
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: 8)?.text, "new draft")
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: 8)?.attachments, [])
        drafts.clearIfMatches(text: "new draft", attachments: [], channelId: 7, parentMessageId: 8)
        XCTAssertNil(drafts.draft(channelId: 7, parentMessageId: 8))
    }

    func testThreadPanelIdentityIncludesTheThreadMessageId() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/MainWindow.swift"),
            encoding: .utf8
        )
        let threadPanel = try XCTUnwrap(source.range(of: "ThreadSidebarView(messageId: threadMessageId)"))
        let followingSource = source[threadPanel.upperBound...]
        let frame = try XCTUnwrap(followingSource.range(of: ".frame(minWidth: 300"))
        XCTAssertTrue(followingSource[..<frame.lowerBound].contains(".id(threadMessageId)"))
    }

    func testDraftsKeepChannelAndThreadContextsSeparate() {
        let drafts = ComposerDrafts()
        drafts.save(text: "channel", attachments: [], channelId: 7, parentMessageId: nil)
        drafts.save(text: "thread", attachments: [], channelId: 7, parentMessageId: 8)
        drafts.save(text: "other", attachments: [], channelId: 9, parentMessageId: nil)
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: nil)?.text, "channel")
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: 8)?.text, "thread")
        XCTAssertEqual(drafts.draft(channelId: 9, parentMessageId: nil)?.text, "other")
    }

    func testAttachmentsSurviveViewReplacementAndClearingRemovesTheSession() {
        let drafts = ComposerDrafts()
        let attachment = PendingAttachment(id: "temp", fileId: "temp", fileName: "file.txt")
        drafts.save(text: "", attachments: [attachment], channelId: 7, parentMessageId: nil)
        XCTAssertEqual(drafts.draft(channelId: 7, parentMessageId: nil)?.attachments, [attachment])
        drafts.clear()
        XCTAssertNil(drafts.draft(channelId: 7, parentMessageId: nil))
    }
}
