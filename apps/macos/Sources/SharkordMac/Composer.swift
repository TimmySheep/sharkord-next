import AppKit
import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

/// The composer's text view. A plain SwiftUI `TextEditor` cannot tell Enter (send) from
/// Shift+Enter (newline), cannot take over ArrowUp on an empty field and cannot intercept
/// pasted images, and all three matter here.
final class ComposerTextView: NSTextView {
    var sendShortcut: KeyboardShortcutBinding? = .returnKey
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEditLast: () -> Void = {}
    var onPasteFiles: ([URL]) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        if sendShortcut?.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) == true {
            onSubmit()

            return
        }

        switch event.keyCode {
        case 53:
            onCancel()

        case 126:
            if event.modifierFlags.isEmpty, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onEditLast()
            } else {
                super.keyDown(with: event)
            }

        default:
            super.keyDown(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []

        if !urls.isEmpty {
            onPasteFiles(urls)

            return
        }

        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("pasted-\(UUID().uuidString).png")

            if let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]),
               (try? png.write(to: temporary)) != nil {
                onPasteFiles([temporary])

                return
            }
        }

        super.paste(sender)
    }
}

struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    var isEnabled: Bool = true
    var minHeight: CGFloat = 42
    var maxHeight: CGFloat = 150
    var sendShortcut: KeyboardShortcutBinding? = .returnKey
    var onTextChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEditLast: () -> Void = {}
    var onPasteFiles: ([URL]) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ComposerTextView(frame: .zero)

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .systemFont(ofSize: 13.5)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.importsGraphics = false
        textView.minSize = NSSize(width: 0, height: 38)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.owner = self
        context.coordinator.minHeight = minHeight
        context.coordinator.maxHeight = maxHeight

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else {
            return
        }

        context.coordinator.owner = self
        context.coordinator.minHeight = minHeight
        context.coordinator.maxHeight = maxHeight

        textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: max(38, textView.frame.height)))
        textView.sendShortcut = sendShortcut
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onEditLast = onEditLast
        textView.onPasteFiles = onPasteFiles

        if textView.string != text {
            textView.string = text
        }

        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor

        context.coordinator.reportHeightIfWidthChanged()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: ComposerTextEditor
        weak var textView: ComposerTextView?
        var minHeight: CGFloat = 42
        var maxHeight: CGFloat = 150

        private var lastWidth: CGFloat = 0
        private var hasReportedInitialHeight = false

        init(owner: ComposerTextEditor) {
            self.owner = owner
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }

            owner.text = textView.string
            owner.onTextChange(textView.string)
            reportHeight()
        }

        /// wrapping changes when the pane is resized, so the measured height can change
        /// even though the text stayed the same
        func reportHeightIfWidthChanged() {
            guard let scrollView = textView?.enclosingScrollView else { return }
            let width = scrollView.contentSize.width

            guard width != lastWidth || !hasReportedInitialHeight else {
                return
            }

            lastWidth = width
            hasReportedInitialHeight = true
            reportHeight()
        }

        private func reportHeight() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }

            let measured = textView.measuredContentHeight(min: minHeight, max: maxHeight)
            scrollView.hasVerticalScroller = measured >= maxHeight

            guard abs(owner.height - measured) > 0.5 else {
                return
            }

            // the measurement happens during a layout pass, so publish it afterwards
            DispatchQueue.main.async { [owner] in
                owner.height = measured
            }
        }
    }
}

/// Grows with the message up to a maximum height, then scrolls.
extension NSTextView {
    func measuredContentHeight(min minHeight: CGFloat, max maxHeight: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else {
            return minHeight
        }

        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2

        return Swift.min(maxHeight, Swift.max(minHeight, used))
    }
}

/// Message composer: text, attachments, reply or edit context, emoji and a send button.
struct Composer: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutsController
    @EnvironmentObject private var drafts: ComposerDrafts

    let channel: SharkordChannel
    var parentMessageId: Int? = nil
    @Binding var replyTarget: SharkordMessage?
    @Binding var editing: SharkordMessage?

    @State private var text = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var uploading = false
    @State private var sending = false
    @State private var textBeforeEditing: String?
    @State private var errorMessage: String?
    @State private var showsEmoji = false
    @State private var composerHeight: CGFloat = 42

    private let composerMinHeight: CGFloat = 42
    private let composerMaxHeight: CGFloat = 150

    private var canSend: Bool {
        session.hasPermission(.sendMessages)
            && session.hasChannelPermission(channel.id, .sendMessages)
    }

    private var canSubmit: Bool {
        if editing != nil { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var canCompose: Bool {
        if let editing {
            return editing.userId == session.ownUserId && editing.editable != false
        }
        return canSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing != nil {
                banner(L10n.t("editingMessage", ns: "macos")) {
                    self.editing = nil
                }
            } else if let replyTarget {
                banner(L10n.t("replyingTo", ns: "common", ["username": session.user(for: replyTarget.userId ?? 0)?.name ?? L10n.t("unknownUser", ns: "common")])) {
                    self.replyTarget = nil
                }
            }

            if !attachments.isEmpty, editing == nil {
                attachmentRow
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L10n.t(canCompose ? "messagePlaceholder" : "messageNotAllowed", ns: "macos"))
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    ComposerTextEditor(
                        text: $text,
                        height: $composerHeight,
                        isEnabled: canCompose && !uploading && !sending,
                        minHeight: composerMinHeight,
                        maxHeight: composerMaxHeight,
                        sendShortcut: keyboardShortcuts.preferences.sendMessage,
                        onTextChange: { _ in signalTyping() },
                        onSubmit: send,
                        onCancel: cancel,
                        onEditLast: editLastOwnMessage,
                        onPasteFiles: { urls in Task { await upload(urls: urls) } }
                    )
                }
                .frame(height: composerHeight)
                .background(Theme.input, in: RoundedRectangle(cornerRadius: 8))

                if canCompose {
                    Button {
                        showsEmoji.toggle()
                    } label: {
                        Image(systemName: "face.smiling")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L10n.t("emojiTab", ns: "common"))
                    .accessibilityLabel(L10n.t("emojiTab", ns: "common"))
                    .disabled(sending)

                    Button(action: pickFiles) {
                        Image(systemName: "paperclip")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L10n.t("attachFiles", ns: "macos"))
                    .accessibilityLabel(L10n.t("attachFiles", ns: "macos"))
                    .disabled(editing != nil || uploading || sending)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSubmit ? Theme.accent : .secondary)
                    .disabled(!canSubmit || uploading || sending)
                    .help(L10n.t(editing == nil ? "sendMessage" : "saveButton", ns: "macos"))
                    .accessibilityLabel(L10n.t(editing == nil ? "sendMessage" : "saveButton", ns: "macos"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.panel)
        .overlay(alignment: .bottomLeading) {
            if showsEmoji {
                EmojiPicker { picked in
                    guard !sending else { return }
                    text += picked
                    showsEmoji = false
                }
                .frame(width: 300, height: 320)
                .background(Theme.deep, in: RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 16)
                .offset(y: -330)
                .padding(.leading, 12)
            }
        }
        .onAppear {
            if let draft = drafts.draft(channelId: channel.id, parentMessageId: parentMessageId) {
                text = draft.text
                attachments = draft.attachments
            }
        }
        .onDisappear(perform: saveDraft)
        .onChange(of: text) { saveDraft() }
        .onChange(of: attachments) { saveDraft() }
        .onChange(of: editing?.id) { oldId, _ in
            if let editing {
                if oldId == nil { textBeforeEditing = text }
                text = MessageHTML.toPlainText(editing.content ?? "")
            } else if let previous = textBeforeEditing {
                text = previous
                textBeforeEditing = nil
            }
        }
    }

    private func banner(_ title: String, onCancel: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.t("cancel", ns: "common"))
            .accessibilityLabel(L10n.t("cancel", ns: "common"))
            .disabled(sending)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 5) {
                        Text(attachment.fileName)
                            .font(.system(size: 11))
                            .lineLimit(1)

                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .disabled(sending)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.elevated, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - actions

    private func send() {
        guard canCompose, canSubmit, !uploading, !sending else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true

        Task {
            defer { sending = false }
            do {
                if let editing {
                    let originalText = MessageHTML.toPlainText(editing.content ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != originalText {
                        try await session.editMessage(editing.id, text: trimmed)
                    }
                    self.editing = nil
                    text = textBeforeEditing ?? ""
                    textBeforeEditing = nil
                    errorMessage = nil
                    saveDraft()
                    return
                } else {
                    let entities = MessageHTML.withEntities(
                        MessageHTML.fromPlainText(trimmed),
                        users: session.users.map { (id: $0.id, name: $0.name) },
                        channels: session.channels.map { (id: $0.id, name: $0.name) }
                    )

                    let html = MessageHTML.withEmoji(
                        entities,
                        emojis: session.emojis.compactMap { emoji in
                            emoji.file.map { (name: emoji.name, src: "/public/\($0.name)") }
                        }
                    )

                    try await session.sendRichMessage(
                        html,
                        channelId: channel.id,
                        replyToMessageId: replyTarget?.id,
                        parentMessageId: parentMessageId,
                        files: attachments.compactMap(\.fileId)
                    )

                    replyTarget = nil
                }

                text = ""
                attachments = []
                errorMessage = nil
                saveDraft()
            } catch {
                errorMessage = SharkordSession.describe(error)
            }
        }
    }

    private func cancel() {
        guard !sending else { return }
        editing = nil
        replyTarget = nil
    }

    private func editLastOwnMessage() {
        guard editing == nil, replyTarget == nil, text.isEmpty else {
            return
        }

        let messages: [SharkordMessage]
        if let parentMessageId {
            messages = session.threadMessages(for: parentMessageId)
        } else {
            messages = session.messagesByChannel[channel.id] ?? []
        }
        let own = messages.last { $0.userId == session.ownUserId && $0.editable != false }

        if let own {
            editing = own
        }
    }

    private func signalTyping() {
        guard canSend, editing == nil else { return }
        session.signalTyping(channelId: channel.id, parentMessageId: parentMessageId)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            Task { await upload(urls: panel.urls) }
        }
    }

    private func upload(urls: [URL]) async {
        guard canSend, editing == nil, !uploading, !sending else { return }
        guard session.hasPermission(.uploadFiles) else {
            errorMessage = L10n.t("noUploadPermission", ns: "common")

            return
        }

        uploading = true
        defer { uploading = false }

        for url in urls {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }

            do {
                let fileId = try await session.uploadAttachment(
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                )

                attachments.append(
                    PendingAttachment(id: fileId, fileId: fileId, fileName: url.lastPathComponent)
                )
            } catch {
                errorMessage = SharkordSession.describe(error)
            }
        }
    }

    private func saveDraft() {
        guard session.ownUserId != 0 else { return }
        drafts.save(
            text: textBeforeEditing ?? text,
            attachments: attachments,
            channelId: channel.id,
            parentMessageId: parentMessageId
        )
    }
}

struct PendingAttachment: Identifiable, Hashable {
    let id: String
    let fileId: String
    let fileName: String
}
