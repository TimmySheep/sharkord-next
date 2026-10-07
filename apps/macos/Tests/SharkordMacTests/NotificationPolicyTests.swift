import XCTest
import UserNotifications
@testable import SharkordMac

final class NotificationPolicyTests: XCTestCase {
    func testPermissionIsRequestedOnlyBeforeTheUserHasDecided() {
        XCTAssertTrue(DesktopNotificationPolicy.shouldRequestAuthorization(for: .notDetermined))
        XCTAssertFalse(DesktopNotificationPolicy.shouldRequestAuthorization(for: .authorized))
        XCTAssertFalse(DesktopNotificationPolicy.shouldRequestAuthorization(for: .denied))
        XCTAssertFalse(DesktopNotificationPolicy.shouldRequestAuthorization(for: .provisional))
    }

    func testOwnMessagesAndVisibleChannelMessagesAreSuppressed() {
        let preferences = DesktopNotificationPreferences(
            allMessages: true,
            mentionsOnly: false,
            directMessages: true,
            replies: true
        )

        XCTAssertFalse(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: true,
            isVisible: false,
            isMention: true,
            isReplyToOwnMessage: true,
            preferences: preferences
        ))
        XCTAssertFalse(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: true,
            isMention: true,
            isReplyToOwnMessage: true,
            preferences: preferences
        ))
    }

    func testDirectMessagesUseTheirOwnPreference() {
        let preferences = DesktopNotificationPreferences(
            allMessages: true,
            mentionsOnly: true,
            directMessages: false,
            replies: true
        )

        XCTAssertFalse(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: true,
            isOwnMessage: false,
            isVisible: false,
            isMention: true,
            isReplyToOwnMessage: true,
            preferences: preferences
        ))
    }

    func testMentionOnlyPreferenceTakesPrecedenceOverAllMessages() {
        let preferences = DesktopNotificationPreferences(
            allMessages: true,
            mentionsOnly: true,
            directMessages: true,
            replies: true
        )

        XCTAssertFalse(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: false,
            isMention: false,
            isReplyToOwnMessage: false,
            preferences: preferences
        ))
        XCTAssertTrue(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: false,
            isMention: true,
            isReplyToOwnMessage: false,
            preferences: preferences
        ))
    }

    func testAllMessagesAndRepliesOnlyPreferences() {
        let allMessages = DesktopNotificationPreferences(
            allMessages: true,
            mentionsOnly: false,
            directMessages: true,
            replies: false
        )
        let repliesOnly = DesktopNotificationPreferences(
            allMessages: false,
            mentionsOnly: false,
            directMessages: true,
            replies: true
        )

        XCTAssertTrue(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: false,
            isMention: false,
            isReplyToOwnMessage: false,
            preferences: allMessages
        ))
        XCTAssertTrue(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: false,
            isMention: false,
            isReplyToOwnMessage: true,
            preferences: repliesOnly
        ))
        XCTAssertFalse(DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: false,
            isOwnMessage: false,
            isVisible: false,
            isMention: false,
            isReplyToOwnMessage: false,
            preferences: repliesOnly
        ))
    }

    func testMentionDetectionMatchesTheMessageRendererVocabulary() {
        let content = "<p>Hello <span class=\"mention\" data-user-id=\"42\" data-name=\"Ada\">@Ada</span></p>"

        XCTAssertTrue(DesktopNotificationPolicy.hasMention(content, userId: 42))
        XCTAssertFalse(DesktopNotificationPolicy.hasMention(content, userId: 7))
    }

    func testNotificationPreviewUsesRenderedTextRatherThanMarkup() {
        let content = "<p>Hello <strong>world</strong><br class=\"hard-break\">again</p>"

        XCTAssertEqual(DesktopNotificationPolicy.plainText(content), "Hello world again")
    }
}
