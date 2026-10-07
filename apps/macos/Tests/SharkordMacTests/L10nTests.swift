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
        L10n.resetStringsCache()
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
        // translations land after the english strings, so a language is briefly behind. the
        // seam reproduces that state instead of shipping a locale that is deliberately
        // incomplete, which is what this used to rely on.
        L10n.overrideStrings(["knownKey": "Kennzahl"], language: "de", ns: "common")
        L10n.language = "de"

        XCTAssertEqual(L10n.t("knownKey"), "Kennzahl")
        XCTAssertEqual(L10n.t("cancel"), "Cancel", "a key the table does not carry falls back to english")

        L10n.resetStringsCache()
    }

    func testSupportedLanguages() {
        XCTAssertEqual(L10n.supportedLanguages.count, 10)
        XCTAssertEqual(
            L10n.supportedLanguages.map(\.code),
            ["en", "de", "es", "fr", "it", "cs", "ru", "zh", "zh-Hant", "pt-BR"]
        )
        // the two chinese tables must stay distinguishable in the language picker
        XCTAssertEqual(L10n.supportedLanguages.first { $0.code == "zh" }?.nativeName, "简体中文")
        XCTAssertEqual(L10n.supportedLanguages.first { $0.code == "zh-Hant" }?.nativeName, "繁體中文")
    }

    func testEverySupportedLanguageIsActuallyTranslated() {
        // de and zh-Hant are the two that were added by hand rather than copied from the web
        // client, so pin a few of their strings to prove the tables are really loaded
        L10n.language = "de"
        XCTAssertEqual(L10n.t("cancel"), "Abbrechen")
        XCTAssertEqual(L10n.t("connectBtn", ns: "connect"), "Verbinden")
        XCTAssertEqual(L10n.t("optional", ns: "connect"), "Optional")

        L10n.language = "zh-Hant"
        XCTAssertEqual(L10n.t("cancel"), "取消")
        XCTAssertEqual(L10n.t("typeAMessage"), "輸入訊息...")
        XCTAssertEqual(L10n.t("simulcastLabel", ns: "settings"), "聯播")
        XCTAssertEqual(L10n.t("optional", ns: "connect"), "可選的")

        // the key that used to leak english on every non-en table
        L10n.language = "zh"
        XCTAssertEqual(L10n.t("messageChannel", ["name": "general"]), "消息「general」")
        XCTAssertEqual(L10n.t("optional", ns: "connect"), "可选的")
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
