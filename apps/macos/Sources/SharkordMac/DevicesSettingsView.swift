import SharkordCore
import SwiftUI

/// Device selection and capture preferences. The pickers are filled by the media
/// engine's own `enumerateDevices`, so the ids match the ones `getUserMedia` will
/// accept inside the voice webview rather than native CoreAudio uids.
struct DevicesSettingsView: View {
    @EnvironmentObject private var voiceMedia: VoiceMediaController

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("devicesTitle", ns: "settings"),
            subtitle: L10n.t("devicesDesc", ns: "settings")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsField(label: L10n.t("microphoneLabel", ns: "settings")) {
                    Picker(selection: microphoneBinding) {
                        Text(L10n.t("defaultMicrophone", ns: "settings"))
                            .tag(String?.none)

                        ForEach(voiceMedia.inputDevices) { device in
                            Text(device.label.isEmpty
                                ? L10n.t("microphonePlaceholder", ns: "settings")
                                : device.label)
                                .tag(String?.some(device.deviceId))
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                SettingsField(label: L10n.t("playbackLabel", ns: "settings")) {
                    Picker(selection: playbackBinding) {
                        Text(L10n.t("defaultOutput", ns: "settings"))
                            .tag(String?.none)

                        ForEach(voiceMedia.outputDevices) { device in
                            Text(device.label.isEmpty
                                ? L10n.t("playbackPlaceholder", ns: "settings")
                                : device.label)
                                .tag(String?.some(device.deviceId))
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                SettingsField(label: L10n.t("webcamLabel", ns: "settings")) {
                    Picker(selection: webcamBinding) {
                        Text(L10n.t("defaultWebcam", ns: "settings"))
                            .tag(String?.none)

                        ForEach(voiceMedia.videoDevices) { device in
                            Text(device.label.isEmpty
                                ? L10n.t("webcamPlaceholder", ns: "settings")
                                : device.label)
                                .tag(String?.some(device.deviceId))
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                Divider()
                    .padding(.vertical, 4)

                Toggle(L10n.t("echoCancellationLabel", ns: "settings"), isOn: echoCancellationBinding)
                    .padding(.bottom, 8)

                Toggle(L10n.t("autoGainControlLabel", ns: "settings"), isOn: autoGainControlBinding)

                Divider()
                    .padding(.vertical, 12)

                microphoneTest
            }
        }
        .task {
            await voiceMedia.reloadDevices()
        }
        .onChange(of: voiceMedia.isMicrophoneTesting) { _, _ in
            // capture permission is requested by the test, after which the device
            // labels become readable, so the list is refreshed once it starts
            Task {
                await voiceMedia.reloadDevices()
            }
        }
    }

    private var microphoneTest: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("microphoneTestLabel", ns: "settings"))
                .font(.system(size: 12, weight: .medium))

            if voiceMedia.isMicrophoneTesting {
                levelBar

                Button(L10n.t("stopTestBtn", ns: "settings")) {
                    voiceMedia.stopMicrophoneTest()
                }
            } else {
                Button(L10n.t("startTestBtn", ns: "settings")) {
                    voiceMedia.startMicrophoneTest()
                }
            }
        }
    }

    private var levelBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))

                Capsule()
                    .fill(Color.green)
                    .frame(width: max(0, geometry.size.width * voiceMedia.microphoneTestLevel))
            }
        }
        .frame(height: 8)
        .frame(maxWidth: 420)
        .accessibilityLabel(L10n.t("microphoneTestLabel", ns: "settings"))
        .accessibilityValue("\(Int(voiceMedia.microphoneTestLevel * 100))%")
    }

    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { voiceMedia.deviceSettings.microphoneId },
            set: { value in update { $0.microphoneId = value } }
        )
    }

    private var playbackBinding: Binding<String?> {
        Binding(
            get: { voiceMedia.deviceSettings.playbackId },
            set: { value in update { $0.playbackId = value } }
        )
    }

    private var webcamBinding: Binding<String?> {
        Binding(
            get: { voiceMedia.deviceSettings.webcamId },
            set: { value in update { $0.webcamId = value } }
        )
    }

    private var echoCancellationBinding: Binding<Bool> {
        Binding(
            get: { voiceMedia.deviceSettings.echoCancellation },
            set: { value in update { $0.echoCancellation = value } }
        )
    }

    private var autoGainControlBinding: Binding<Bool> {
        Binding(
            get: { voiceMedia.deviceSettings.autoGainControl },
            set: { value in update { $0.autoGainControl = value } }
        )
    }

    private func update(_ mutate: (inout VoiceDeviceSettings) -> Void) {
        var settings = voiceMedia.deviceSettings
        mutate(&settings)
        voiceMedia.updateDeviceSettings(settings)
    }
}
