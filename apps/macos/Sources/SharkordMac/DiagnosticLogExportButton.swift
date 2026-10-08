import AppKit
import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticLogExportButton: View {
    @State private var showsResult = false
    @State private var didExport = false

    var body: some View {
        Button(action: exportLogs) {
            Label(L10n.t("exportLogs", ns: "macos"), systemImage: "square.and.arrow.up")
        }
        .alert(isPresented: $showsResult) {
            let title = didExport ? "logsExportSuccessTitle" : "logsExportFailureTitle"
            let message = didExport ? "logsExportSuccessMessage" : "logsExportFailureMessage"

            return Alert(
                title: Text(L10n.t(title, ns: "macos")),
                message: Text(L10n.t(message, ns: "macos")),
                dismissButton: .default(Text(L10n.t("close", ns: "common")))
            )
        }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "cove-diagnostics-\(formatter.string(from: Date())).log"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        ClientLogStore.shared.recordInfo("diagnostics.export")

        do {
            try ClientLogStore.shared.exportLogs(to: destinationURL)
            didExport = true
        } catch {
            ClientLogStore.shared.recordError("diagnostics.export.failed", error: error)
            didExport = false
        }

        showsResult = true
    }
}
