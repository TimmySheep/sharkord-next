import Foundation
import Testing

@testable import SharkordCore

@Suite
struct VoiceDeviceSettingsTests {
    @Test func defaultsUseThePlatformDeviceAndEnableBothAudioTreatments() {
        let settings = VoiceDeviceSettings.default

        #expect(settings.microphoneId == nil)
        #expect(settings.playbackId == nil)
        #expect(settings.webcamId == nil)
        #expect(settings.echoCancellation)
        #expect(settings.autoGainControl)
    }

    @Test func bridgePayloadSendsEmptyIdsSoTheWorkerFallsBackToDefaults() {
        let payload = VoiceDeviceSettings.default.bridgePayload

        #expect(payload["microphoneId"] as? String == "")
        #expect(payload["playbackId"] as? String == "")
        #expect(payload["webcamId"] as? String == "")
        #expect(payload["echoCancellation"] as? Bool == true)
        #expect(payload["autoGainControl"] as? Bool == true)
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        let original = VoiceDeviceSettings(
            microphoneId: "mic-1",
            playbackId: "out-1",
            webcamId: "cam-1",
            echoCancellation: false,
            autoGainControl: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceDeviceSettings.self, from: data)

        #expect(decoded == original)
    }

    @Test func resolutionDropsIdsWhoseDeviceIsGoneButKeepsAttachedOnes() {
        let devices = VoiceEnumeratedDevices(
            inputs: [VoiceMediaDevice(deviceId: "mic-2", label: "Mic")],
            outputs: [],
            videos: [VoiceMediaDevice(deviceId: "cam-9", label: "Cam")]
        )
        let settings = VoiceDeviceSettings(
            microphoneId: "mic-gone",
            playbackId: "out-gone",
            webcamId: "cam-9",
            echoCancellation: true,
            autoGainControl: true
        )

        let resolved = devices.resolved(settings)

        #expect(resolved.microphoneId == nil)
        // an unreadable output list is left alone rather than clearing a valid choice
        #expect(resolved.playbackId == "out-gone")
        #expect(resolved.webcamId == "cam-9")
    }

    @Test func resolutionLeavesSettingsUntouchedWhenNoDeviceLabelsAreReadable() {
        let settings = VoiceDeviceSettings(microphoneId: "mic-1", playbackId: "out-1", webcamId: "cam-1")

        #expect(VoiceEnumeratedDevices.empty.resolved(settings) == settings)
    }

    @Test func storeRoundTripsThroughUserDefaults() throws {
        let suite = "VoiceDeviceSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceDeviceSettings(
            microphoneId: "mic-3",
            playbackId: "out-3",
            webcamId: "cam-3",
            echoCancellation: false,
            autoGainControl: true
        )

        VoiceDeviceSettingsStore.save(settings, to: defaults)

        #expect(VoiceDeviceSettingsStore.load(from: defaults) == settings)
    }

    @Test func storeFallsBackToDefaultsWhenStoredDataIsUnreadable() throws {
        let suite = "VoiceDeviceSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: VoiceDeviceSettingsStore.storageKey)

        #expect(VoiceDeviceSettingsStore.load(from: defaults) == .default)
    }
}
