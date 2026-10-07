import AppKit
import XCTest
@testable import SharkordMac

final class KeyboardShortcutsTests: XCTestCase {
    func testDefaultSendsOnReturnAndLeavesVoiceActionsUnassigned() {
        let preferences = KeyboardShortcutPreferences()

        XCTAssertEqual(preferences.sendMessage, .returnKey)
        XCTAssertNil(preferences.muteMicrophone)
        XCTAssertNil(preferences.unmuteMicrophone)
        XCTAssertNil(preferences.muteVoiceAudio)
        XCTAssertNil(preferences.unmuteVoiceAudio)
    }

    func testReturnBindingMatchesReturnAndKeypadEnterOnlyWithoutExtraModifiers() {
        let binding = KeyboardShortcutBinding.returnKey

        XCTAssertTrue(binding.matches(keyCode: 36, modifiers: []))
        XCTAssertTrue(binding.matches(keyCode: 76, modifiers: []))
        XCTAssertFalse(binding.matches(keyCode: 36, modifiers: .shift))
        XCTAssertFalse(binding.matches(keyCode: 36, modifiers: .command))
    }

    func testCommandReturnCanBeAssignedToSendMessage() {
        var preferences = KeyboardShortcutPreferences()
        let commandReturn = KeyboardShortcutBinding(
            keyCode: 36,
            modifiers: .command,
            keyLabel: "↩"
        )

        XCTAssertNil(preferences.assign(commandReturn, to: .sendMessage))
        XCTAssertEqual(preferences.sendMessage, commandReturn)
        XCTAssertEqual(commandReturn.displayString, "⌘↩")
    }

    func testShortcutAssignmentsRejectConflictsAndUnmodifiedVoiceKeys() {
        var preferences = KeyboardShortcutPreferences()
        let mute = KeyboardShortcutBinding(keyCode: 46, modifiers: .command, keyLabel: "M")
        let bareLetter = KeyboardShortcutBinding(keyCode: 46, modifiers: [], keyLabel: "M")

        XCTAssertNil(preferences.assign(mute, to: .muteMicrophone))
        XCTAssertEqual(
            preferences.assign(mute, to: .unmuteMicrophone),
            .alreadyAssigned(.muteMicrophone)
        )
        XCTAssertEqual(
            preferences.assign(bareLetter, to: .unmuteMicrophone),
            .modifierRequired
        )
        XCTAssertEqual(preferences.muteMicrophone, mute)
        XCTAssertNil(preferences.unmuteMicrophone)
    }

    func testReturnAliasesCannotBeAssignedTwice() {
        var preferences = KeyboardShortcutPreferences()
        let keypadCommandReturn = KeyboardShortcutBinding(
            keyCode: 76,
            modifiers: .command,
            keyLabel: "↩"
        )

        XCTAssertNil(preferences.assign(keypadCommandReturn, to: .sendMessage))
        XCTAssertEqual(
            preferences.assign(
                KeyboardShortcutBinding(keyCode: 36, modifiers: .command, keyLabel: "↩"),
                to: .muteMicrophone
            ),
            .alreadyAssigned(.sendMessage)
        )
    }

    func testF13RemainsReservedForPushToTalk() {
        var preferences = KeyboardShortcutPreferences()
        let commandF13 = KeyboardShortcutBinding(keyCode: 105, modifiers: .command, keyLabel: "F13")

        XCTAssertEqual(
            preferences.assign(commandF13, to: .muteMicrophone),
            .reservedForPushToTalk
        )
    }

    func testShiftReturnRemainsReservedForLineBreaks() {
        var preferences = KeyboardShortcutPreferences()
        let shiftReturn = KeyboardShortcutBinding(
            keyCode: 36,
            modifiers: .shift,
            keyLabel: "↩"
        )

        XCTAssertEqual(
            preferences.assign(shiftReturn, to: .sendMessage),
            .returnReservedForNewline
        )
        XCTAssertEqual(preferences.sendMessage, .returnKey)
    }

    func testPreferencesRoundTripThroughCodable() throws {
        var preferences = KeyboardShortcutPreferences()
        let mute = KeyboardShortcutBinding(keyCode: 46, modifiers: .command, keyLabel: "M")
        XCTAssertNil(preferences.assign(mute, to: .muteMicrophone))

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(KeyboardShortcutPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }

    @MainActor
    func testControllerPersistsAssignmentsInProvidedDefaults() throws {
        let suiteName = "KeyboardShortcutsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = KeyboardShortcutsController(defaults: defaults)
        let commandReturn = KeyboardShortcutBinding(
            keyCode: 36,
            modifiers: .command,
            keyLabel: "↩"
        )

        XCTAssertNil(controller.assign(commandReturn, to: .sendMessage))
        XCTAssertEqual(
            KeyboardShortcutsController(defaults: defaults).preferences.sendMessage,
            commandReturn
        )
    }
}
