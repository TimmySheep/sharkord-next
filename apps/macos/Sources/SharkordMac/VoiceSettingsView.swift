import SharkordCore
import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject private var voiceMedia: VoiceMediaController

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("microphoneLabel", ns: "settings"),
            subtitle: L10n.t("noiseSuppressionMixDescription", ns: "settings")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("noiseSuppressionLabel", ns: "settings"))
                    .font(.system(size: 12, weight: .medium))

                Text(L10n.t("noiseSuppressionRnnoiseNotes", ns: "settings"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("0%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Slider(value: noiseSuppressionMix, in: 0...1, step: 0.01)
                        .accessibilityLabel(L10n.t("noiseSuppressionLabel", ns: "settings"))
                        .accessibilityValue("\(Int(voiceMedia.noiseSuppressionMix * 100))%")

                    Text("100%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 420)
            }
            .padding(.vertical, 8)
        }
    }

    private var noiseSuppressionMix: Binding<Double> {
        Binding(
            get: { voiceMedia.noiseSuppressionMix },
            set: { voiceMedia.setNoiseSuppressionMix($0) }
        )
    }
}
