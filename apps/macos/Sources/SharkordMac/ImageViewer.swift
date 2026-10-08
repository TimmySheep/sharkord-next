import AppKit
import SwiftUI

enum ImageViewerZoom {
    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 0.5), 3)
    }
}

struct ImageViewerView: View {
    private enum CopyState {
        case idle
        case copied
        case failed
    }

    let imageURL: URL
    let altText: String

    @Environment(\.dismiss) private var dismiss
    @GestureState private var magnification = 1.0
    @GestureState private var dragTranslation = CGSize.zero
    @State private var committedScale = 1.0
    @State private var committedOffset = CGSize.zero
    @State private var copyState = CopyState.idle

    private var displayedScale: CGFloat {
        ImageViewerZoom.clamped(committedScale * magnification)
    }

    private var displayedOffset: CGSize {
        CGSize(
            width: committedOffset.width + dragTranslation.width,
            height: committedOffset.height + dragTranslation.height
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            image
                .scaleEffect(displayedScale)
                .offset(displayedOffset)
                .contentShape(Rectangle())
                .gesture(imageGestures)

            VStack {
                HStack(spacing: 8) {
                    Spacer()

                    Button(action: copyImageLink) {
                        Label(copyButtonTitle, systemImage: copyButtonIcon)
                    }
                    .help(L10n.t("imageViewerCopyLink", ns: "macos"))

                    Button {
                        dismiss()
                    } label: {
                        Label(L10n.t("close", ns: "common"), systemImage: "xmark")
                    }
                    .help(L10n.t("close", ns: "common"))
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: zoomOut) {
                        Label(L10n.t("imageViewerZoomOut", ns: "macos"), systemImage: "minus.magnifyingglass")
                    }
                    .disabled(committedScale <= 0.5)
                    .help(L10n.t("imageViewerZoomOut", ns: "macos"))

                    Text("\(Int(displayedScale * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 46)

                    Button(action: zoomIn) {
                        Label(L10n.t("imageViewerZoomIn", ns: "macos"), systemImage: "plus.magnifyingglass")
                    }
                    .disabled(committedScale >= 3)
                    .help(L10n.t("imageViewerZoomIn", ns: "macos"))

                    Button(action: resetZoom) {
                        Label(L10n.t("imageViewerResetZoom", ns: "macos"), systemImage: "arrow.counterclockwise")
                    }
                    .help(L10n.t("imageViewerResetZoom", ns: "macos"))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(Color.black)
        .onExitCommand {
            dismiss()
        }
        .accessibilityAction(named: L10n.t("close", ns: "common")) {
            dismiss()
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var image: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(altText)
            case .failure:
                ContentUnavailableView(
                    L10n.t("imagePreviewUnavailable", ns: "macos"),
                    systemImage: "photo"
                )
                .foregroundStyle(.white)
            case .empty:
                ProgressView()
                    .tint(.white)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageGestures: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .updating($magnification) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    committedScale = ImageViewerZoom.clamped(committedScale * value)
                },
            DragGesture(minimumDistance: 2)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    committedOffset.width += value.translation.width
                    committedOffset.height += value.translation.height
                }
        )
    }

    private var copyButtonTitle: String {
        switch copyState {
        case .idle:
            return L10n.t("imageViewerCopyLink", ns: "macos")
        case .copied:
            return L10n.t("imageLinkCopied", ns: "common")
        case .failed:
            return L10n.t("failedCopyImageLink", ns: "common")
        }
    }

    private var copyButtonIcon: String {
        switch copyState {
        case .idle:
            return "link"
        case .copied:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func zoomIn() {
        committedScale = ImageViewerZoom.clamped(committedScale * 1.25)
    }

    private func zoomOut() {
        committedScale = ImageViewerZoom.clamped(committedScale / 1.25)
    }

    private func resetZoom() {
        committedScale = 1
        committedOffset = .zero
    }

    private func copyImageLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copyState = pasteboard.setString(imageURL.absoluteString, forType: .string) ? .copied : .failed
    }

}
