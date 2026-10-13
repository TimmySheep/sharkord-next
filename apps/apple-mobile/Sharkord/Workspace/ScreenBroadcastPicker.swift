import ReplayKit
import SwiftUI
import UIKit

struct ScreenBroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = ScreenBroadcastConfiguration.extensionIdentifier
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        picker.preferredExtension = ScreenBroadcastConfiguration.extensionIdentifier
    }
}
