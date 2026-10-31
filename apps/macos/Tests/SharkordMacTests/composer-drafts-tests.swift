import XCTest
@testable import SharkordMac

@MainActor
final class ComposerDraftsTests: XCTestCase {
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
