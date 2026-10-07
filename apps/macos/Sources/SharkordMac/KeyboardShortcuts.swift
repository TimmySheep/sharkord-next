import AppKit
import Combine
import Foundation
import SharkordCore

enum KeyboardShortcutAction: String, CaseIterable, Identifiable {
    case sendMessage
    case muteMicrophone
    case unmuteMicrophone
    case muteVoiceAudio
    case unmuteVoiceAudio

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .sendMessage:
            return "keyboardShortcutSendTitle"
        case .muteMicrophone:
            return "keyboardShortcutMuteMicrophoneTitle"
        case .unmuteMicrophone:
            return "keyboardShortcutUnmuteMicrophoneTitle"
        case .muteVoiceAudio:
            return "keyboardShortcutMuteVoiceAudioTitle"
        case .unmuteVoiceAudio:
            return "keyboardShortcutUnmuteVoiceAudioTitle"
        }
    }

    var descriptionKey: String? {
        switch self {
        case .sendMessage:
            return "keyboardShortcutSendDescription"
        case .muteMicrophone:
            return "keyboardShortcutMuteMicrophoneDescription"
        case .unmuteMicrophone:
            return "keyboardShortcutUnmuteMicrophoneDescription"
        case .muteVoiceAudio:
            return "keyboardShortcutMuteVoiceAudioDescription"
        case .unmuteVoiceAudio:
            return "keyboardShortcutUnmuteVoiceAudioDescription"
        }
    }

    var requiresVoiceConnection: Bool {
        self != .sendMessage
    }
}

struct KeyboardShortcutBinding: Codable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt
    let keyLabel: String

    static let returnKey = KeyboardShortcutBinding(
        keyCode: 36,
        modifiers: [],
        keyLabel: "↩"
    )

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = Self.normalizedModifiers(modifiers)
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let keyCode = event.keyCode
        guard let keyLabel = Self.label(for: event) else {
            return nil
        }

        self.init(keyCode: keyCode, modifiers: event.modifierFlags, keyLabel: keyLabel)
    }

    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result = ""

        if flags.contains(.control) {
            result += "⌃"
        }
        if flags.contains(.option) {
            result += "⌥"
        }
        if flags.contains(.shift) {
            result += "⇧"
        }
        if flags.contains(.command) {
            result += "⌘"
        }

        return result + keyLabel
    }

    var isReturnKey: Bool {
        keyCode == 36 || keyCode == 76
    }

    var hasPrimaryModifier: Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return !flags.intersection([.command, .option, .control]).isEmpty
    }

    var conflictsWithPushToTalk: Bool {
        keyCode == 105
    }

    func hasSameTrigger(as other: KeyboardShortcutBinding) -> Bool {
        let sameKey = keyCode == other.keyCode || (isReturnKey && other.isReturnKey)
        return sameKey && modifiers == other.modifiers
    }

    func matches(keyCode pressedKeyCode: UInt16, modifiers pressedModifiers: NSEvent.ModifierFlags) -> Bool {
        let keyMatches = keyCode == pressedKeyCode
            || (isReturnKey && (pressedKeyCode == 36 || pressedKeyCode == 76))

        return keyMatches && modifiers == Self.normalizedModifiers(pressedModifiers)
    }

    private static func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> UInt {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
            .rawValue
    }

    private static func label(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76:
            return "↩"
        case 48:
            return "⇥"
        case 49:
            return "␣"
        case 51:
            return "⌫"
        case 53:
            return "⎋"
        case 117:
            return "⌦"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        case 105:
            return "F13"
        default:
            return event.charactersIgnoringModifiers?.uppercased().nilIfEmpty
        }
    }
}

struct KeyboardShortcutPreferences: Codable, Equatable {
    var sendMessage: KeyboardShortcutBinding?
    var muteMicrophone: KeyboardShortcutBinding?
    var unmuteMicrophone: KeyboardShortcutBinding?
    var muteVoiceAudio: KeyboardShortcutBinding?
    var unmuteVoiceAudio: KeyboardShortcutBinding?

    init(
        sendMessage: KeyboardShortcutBinding? = .returnKey,
        muteMicrophone: KeyboardShortcutBinding? = nil,
        unmuteMicrophone: KeyboardShortcutBinding? = nil,
        muteVoiceAudio: KeyboardShortcutBinding? = nil,
        unmuteVoiceAudio: KeyboardShortcutBinding? = nil
    ) {
        self.sendMessage = sendMessage
        self.muteMicrophone = muteMicrophone
        self.unmuteMicrophone = unmuteMicrophone
        self.muteVoiceAudio = muteVoiceAudio
        self.unmuteVoiceAudio = unmuteVoiceAudio
    }

    func binding(for action: KeyboardShortcutAction) -> KeyboardShortcutBinding? {
        switch action {
        case .sendMessage:
            return sendMessage
        case .muteMicrophone:
            return muteMicrophone
        case .unmuteMicrophone:
            return unmuteMicrophone
        case .muteVoiceAudio:
            return muteVoiceAudio
        case .unmuteVoiceAudio:
            return unmuteVoiceAudio
        }
    }

    mutating func assign(
        _ binding: KeyboardShortcutBinding?,
        to action: KeyboardShortcutAction
    ) -> KeyboardShortcutAssignmentError? {
        if let binding {
            if binding.conflictsWithPushToTalk {
                return .reservedForPushToTalk
            }

            let flags = NSEvent.ModifierFlags(rawValue: binding.modifiers)
            let hasOnlyShift = flags == .shift
            if action == .sendMessage, binding.isReturnKey, hasOnlyShift {
                return .returnReservedForNewline
            }

            let bareReturnSend = action == .sendMessage && binding.isReturnKey && flags.isEmpty
            if !binding.hasPrimaryModifier && !bareReturnSend {
                return .modifierRequired
            }

            if let conflict = KeyboardShortcutAction.allCases.first(where: {
                guard $0 != action, let existing = self.binding(for: $0) else {
                    return false
                }

                return existing.hasSameTrigger(as: binding)
            }) {
                return .alreadyAssigned(conflict)
            }
        }

        set(binding, for: action)
        return nil
    }

    private mutating func set(_ binding: KeyboardShortcutBinding?, for action: KeyboardShortcutAction) {
        switch action {
        case .sendMessage:
            sendMessage = binding
        case .muteMicrophone:
            muteMicrophone = binding
        case .unmuteMicrophone:
            unmuteMicrophone = binding
        case .muteVoiceAudio:
            muteVoiceAudio = binding
        case .unmuteVoiceAudio:
            unmuteVoiceAudio = binding
        }
    }
}

enum KeyboardShortcutAssignmentError: Equatable {
    case modifierRequired
    case returnReservedForNewline
    case reservedForPushToTalk
    case alreadyAssigned(KeyboardShortcutAction)
}

@MainActor
final class KeyboardShortcutsController: ObservableObject {
    @Published private(set) var preferences: KeyboardShortcutPreferences
    @Published private(set) var recordingAction: KeyboardShortcutAction?

    private let defaults: UserDefaults
    private weak var session: SharkordSession?
    private weak var voiceMedia: VoiceMediaController?
    private var localMonitor: Any?
    private var mediaTask: Task<Void, Never>?

    private static let defaultsKey = "keyboard.shortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(KeyboardShortcutPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = KeyboardShortcutPreferences()
        }
    }

    func startMonitoring(session: SharkordSession, voiceMedia: VoiceMediaController) {
        self.session = session
        self.voiceMedia = voiceMedia

        guard localMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handle(event)
        }
    }

    func beginRecording(_ action: KeyboardShortcutAction) {
        recordingAction = action
    }

    func cancelRecording() {
        recordingAction = nil
    }

    @discardableResult
    func assign(
        _ binding: KeyboardShortcutBinding?,
        to action: KeyboardShortcutAction
    ) -> KeyboardShortcutAssignmentError? {
        if let error = preferences.assign(binding, to: action) {
            return error
        }

        persistPreferences()
        recordingAction = nil
        return nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recordingAction == nil else {
            return event
        }

        guard let action = KeyboardShortcutAction.allCases.first(where: { action in
            guard action.requiresVoiceConnection,
                  let binding = preferences.binding(for: action) else {
                return false
            }

            return binding.matches(keyCode: event.keyCode, modifiers: event.modifierFlags)
        }) else {
            return event
        }

        guard canPerformVoiceAction(action) else {
            return event
        }

        if !event.isARepeat {
            performVoiceAction(action)
        }

        return nil
    }

    private func canPerformVoiceAction(_ action: KeyboardShortcutAction) -> Bool {
        guard action.requiresVoiceConnection,
              let session,
              let voiceMedia,
              let channelId = session.currentVoiceChannelId,
              voiceMedia.status == "connected" else {
            return false
        }

        guard action == .unmuteMicrophone else {
            return true
        }

        return session.hasChannelPermission(channelId, .speak)
            && session.voiceMap[channelId]?
                .users[String(session.ownUserId)]?.soundMuted != true
            && voiceMedia.canPublishAudio
    }

    private func performVoiceAction(_ action: KeyboardShortcutAction) {
        guard canPerformVoiceAction(action),
              let voiceMedia else {
            return
        }

        let shouldMute: Bool
        let context: String

        switch action {
        case .sendMessage:
            return
        case .muteMicrophone:
            shouldMute = true
            context = "microphone"
        case .unmuteMicrophone:
            shouldMute = false
            context = "microphone"
        case .muteVoiceAudio:
            shouldMute = true
            context = "audio"
        case .unmuteVoiceAudio:
            shouldMute = false
            context = "audio"
        }

        let previousTask = mediaTask
        mediaTask = Task { [weak self] in
            await previousTask?.value

            do {
                if context == "microphone" {
                    try await voiceMedia.setMicrophoneMuted(shouldMute)
                } else {
                    try await voiceMedia.setOutputMuted(shouldMute)
                }
            } catch {
                self?.voiceMedia?.presentError(error.localizedDescription, context: context)
            }
        }
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        defaults.set(data, forKey: Self.defaultsKey)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
