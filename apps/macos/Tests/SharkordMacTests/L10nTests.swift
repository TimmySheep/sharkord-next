import XCTest
@testable import SharkordMac

final class L10nTests: XCTestCase {
    private var originalLanguage = ""

    override func setUp() {
        super.setUp()
        originalLanguage = L10n.language
        L10n.language = "en"
    }

    override func tearDown() {
        L10n.language = originalLanguage
        super.tearDown()
    }

    func testKnownKeyReturnsEnglishString() {
        XCTAssertEqual(L10n.t("cancel"), "Cancel")
        XCTAssertEqual(L10n.t("retry"), "Retry")
        XCTAssertEqual(L10n.t("connectionLost", ns: "disconnected"), "Connection lost")
        XCTAssertEqual(L10n.t("goToConnectScreen", ns: "disconnected"), "Go to Connect Screen")
    }

    func testInterpolationReplacesPlaceholders() {
        XCTAssertEqual(L10n.t("memberSince", ["date": "March 2024"]), "Member since March 2024")
        XCTAssertEqual(L10n.t("messageChannel", ["name": "general"]), "Message \"general\"")
        XCTAssertEqual(
            L10n.t("reconnectingAttempt", ["attempt": 2, "total": 5]),
            "Attempt 2 of 5"
        )
    }

    func testPluralVariantsSelectedByCount() {
        XCTAssertEqual(L10n.t("reply", ["count": 1]), "1 reply")
        XCTAssertEqual(L10n.t("reply", ["count": 3]), "3 replies")
    }

    func testUnknownKeyFallsBackToKeyItself() {
        XCTAssertEqual(L10n.t("thisKeyDoesNotExist"), "thisKeyDoesNotExist")
        XCTAssertEqual(L10n.t("missing.nested", ns: "settings"), "missing.nested")
    }

    func testLanguageSwitchChangesString() {
        XCTAssertEqual(L10n.t("cancel"), "Cancel")
        L10n.language = "zh"
        XCTAssertEqual(L10n.t("cancel"), "取消")
        XCTAssertEqual(L10n.t("memberSince", ["date": "2024"]), "加入于 2024")
    }

    func testMissingTranslationFallsBackToEnglish() {
        // messageChannel exists in english but not in cs or zh
        L10n.language = "cs"
        XCTAssertEqual(L10n.t("messageChannel", ["name": "general"]), "Message \"general\"")
        L10n.language = "zh"
        XCTAssertEqual(L10n.t("typeAMessage"), "Type a message...")
    }

    func testSupportedLanguages() {
        XCTAssertEqual(L10n.supportedLanguages.count, 8)
        XCTAssertEqual(
            L10n.supportedLanguages.map(\.code),
            ["en", "cs", "es", "fr", "it", "ru", "zh", "pt-BR"]
        )
        XCTAssertTrue(L10n.supportedLanguages.contains { $0.code == "pt-BR" })
    }

    func testLocaleResourcesLoadedFromBundle() {
        // nested keys exercise the flattening of permissions.json and connect.json
        XCTAssertEqual(L10n.t("headers.server", ns: "permissions"), "Permissions")
        XCTAssertEqual(L10n.t("server.MANAGE_ROLES", ns: "permissions"), "Manage roles")
        XCTAssertEqual(
            L10n.t("oidcError.access_denied", ns: "connect"),
            "Your identity provider refused the sign in."
        )
    }

    func testDateHelpersUseLanguageLocale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(L10n.date(date, style: .short).isEmpty)
        XCTAssertFalse(L10n.date(date, style: .dateTime).isEmpty)
        XCTAssertFalse(L10n.relative(date).isEmpty)
    }
}
