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

    var suggestionActive: () -> Bool = { false }
    var suggestionReplacement: () -> (range: NSRange, text: String)? = { nil }
    var onSuggestionNavigate: (Int) -> Void = { _ in }
    var onSuggestionAccepted: () -> Void = {}
    var onSuggestionCancelled: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // escape closes the suggestion menu first, then falls through to the usual cancel
        if event.keyCode == 53 {
            if suggestionActive() {
                onSuggestionCancelled()
            } else {
                onCancel()
            }

            return
        }

        // tab accepts the highlighted suggestion
        if event.keyCode == 48, suggestionActive() {
            acceptSelectedSuggestion()

            return
        }

        if event.keyCode == 125, suggestionActive() {
            onSuggestionNavigate(1)

            return
        }

        if sendShortcut?.matches(keyCode: event.keyCode, modifiers: modifiers) == true {
            // enter accepts a pending suggestion instead of sending
            if suggestionActive() {
                acceptSelectedSuggestion()
            } else {
                onSubmit()
            }

            return
        }

        if event.keyCode == 126, modifiers.isEmpty {
            if suggestionActive() {
                onSuggestionNavigate(-1)
            } else if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onEditLast()
            } else {
                super.keyDown(with: event)
            }

            return
        }

        super.keyDown(with: event)
    }

    /// replaces the active suggestion token in place, keeping undo and caret placement intact.
    func acceptSelectedSuggestion() {
        guard let replacement = suggestionReplacement() else { return }
        let range = replacement.range
        let insert = replacement.text
        guard range.location + range.length <= (string as NSString).length else { return }

        if shouldChangeText(in: range, replacementString: insert) {
            replaceCharacters(in: range, with: insert)
            setSelectedRange(NSRange(location: range.location + (insert as NSString).length, length: 0))
            didChangeText()
        }

        onSuggestionAccepted()
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        let urls = (board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []).filter(\.isFileURL)

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
    var onSelectionChange: (Int) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEditLast: () -> Void = {}
    var onPasteFiles: ([URL]) -> Void = { _ in }
    var onEditorReady: ((ComposerTextView) -> Void)? = nil
    var suggestionActive: () -> Bool = { false }
    var suggestionReplacement: () -> (range: NSRange, text: String)? = { nil }
    var onSuggestionNavigate: (Int) -> Void = { _ in }
    var onSuggestionAccepted: () -> Void = {}
    var onSuggestionCancelled: () -> Void = {}

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

        onEditorReady?(textView)

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
        textView.suggestionActive = suggestionActive
        textView.suggestionReplacement = suggestionReplacement
        textView.onSuggestionNavigate = onSuggestionNavigate
        textView.onSuggestionAccepted = onSuggestionAccepted
        textView.onSuggestionCancelled = onSuggestionCancelled

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

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }

            owner.onSelectionChange(textView.selectedRange().location)
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
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadProgress: Double = 0
    @State private var uploadName = ""
    @State private var removing: Set<String> = []
    @State private var isVisible = false
    @State private var sending = false
    @State private var textBeforeEditing: String?
    @State private var errorMessage: String?
    @State private var showsEmoji = false
    @State private var composerHeight: CGFloat = 42
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var suggestionQuery: ComposerSuggestionQuery?
    @State private var suggestionItems: [ComposerSuggestionItem] = []
    @State private var suggestionIndex = 0
    @State private var suggestionsSuppressed = false
    @State private var editor = EditorHandle()

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
            if uploading {
                HStack {
                    ProgressView(value: uploadProgress).frame(maxWidth: 160)
                    Text(uploadName).font(.caption).lineLimit(1)
                    Text("\(Int(uploadProgress * 100))%").font(.caption.monospacedDigit())
                    Button(L10n.t("cancel", ns: "common")) { uploadTask?.cancel() }
                }.padding(.horizontal, 12).padding(.top, 6)
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
                        isEnabled: canCompose && !sending,
                        minHeight: composerMinHeight,
                        maxHeight: composerMaxHeight,
                        sendShortcut: keyboardShortcuts.preferences.sendMessage,
                        onTextChange: handleTextChange,
                        onSelectionChange: handleSelectionChange,
                        onSubmit: send,
                        onCancel: cancel,
                        onEditLast: editLastOwnMessage,
                        onPasteFiles: startUpload,
                        onEditorReady: { editor.textView = $0 },
                        suggestionActive: { !suggestionItems.isEmpty },
                        suggestionReplacement: currentSuggestionReplacement,
                        onSuggestionNavigate: moveSuggestion,
                        onSuggestionAccepted: { suggestionIndex = 0 },
                        onSuggestionCancelled: suppressSuggestions
                    )
                }
                .frame(height: composerHeight)
                .background(Theme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if !showsEmoji, !suggestionItems.isEmpty {
                        suggestionMenu
                            .offset(y: -(CGFloat(suggestionItems.count) * 30 + 20))
                    }
                }

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
                    .disabled(!canSubmit || uploading || sending || !removing.isEmpty)
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
            isVisible = true
            if let draft = drafts.draft(channelId: channel.id, parentMessageId: parentMessageId) {
                text = draft.text
                attachments = draft.attachments
            }
        }
        .onDisappear { uploadTask?.cancel(); saveDraft(); isVisible = false }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.allSatisfy(\.isFileURL), !urls.isEmpty else { return false }
            startUpload(urls)
            return true
        }
        .onChange(of: text) { saveDraft() }
        .onChange(of: attachments) { saveDraft() }
        .onChange(of: editing?.id) { oldId, _ in
            if let editing {
                if oldId == nil { textBeforeEditing = text }
                text = MessageHTML.toComposerText(editing.content ?? "")
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
                            removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .disabled(sending || removing.contains(attachment.id))
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

    private var suggestionMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(suggestionItems.enumerated()), id: \.element.id) { index, item in
                SuggestionRow(item: item, highlighted: index == suggestionIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { acceptSuggestion(at: index) }
            }
        }
        .padding(6)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 10)
    }

    // MARK: - actions

    private func send() {
        guard canCompose, canSubmit, !uploading, !sending, removing.isEmpty else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentText = text
        let sentAttachments = attachments
        let messageToEdit = editing
        let replyId = replyTarget?.id
        let ownerId = session.ownUserId
        let serverId = session.serverId
        sending = true

        Task {
            defer { sending = false }
            do {
                if let editing = messageToEdit {
                    let originalText = MessageHTML.toComposerText(editing.content ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != originalText {
                        try await session.editMessage(editing.id, text: trimmed)
                    }
                    guard ownerId == session.ownUserId, serverId == session.serverId else { return }
                    if isVisible { self.editing = nil }
                    text = textBeforeEditing ?? ""
                    textBeforeEditing = nil
                    errorMessage = nil
                    saveDraft()
                    return
                } else {
                    let html = MessageHTML.fromComposerText(
                        trimmed,
                        users: session.users.map { (id: $0.id, name: $0.name) },
                        channels: session.channels.map { (id: $0.id, name: $0.name) },
                        emojis: session.emojis.compactMap { emoji in
                            emoji.file.map { (name: emoji.name, src: "/public/\($0.name)") }
                        },
                        emojiGlyph: { EmojiCatalog.glyph(for: $0) }
                    )

                    try await session.sendRichMessage(
                        html,
                        channelId: channel.id,
                        replyToMessageId: replyId,
                        parentMessageId: parentMessageId,
                        files: sentAttachments.map(\.fileId)
                    )

                    guard ownerId == session.ownUserId, serverId == session.serverId else { return }
                    if isVisible { replyTarget = nil }
                }

                text = ""
                attachments = []
                errorMessage = nil
                drafts.clearIfMatches(text: sentText, attachments: sentAttachments, channelId: channel.id, parentMessageId: parentMessageId)
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

    private func handleTextChange(_ value: String) {
        suggestionsSuppressed = false
        signalTyping()
        updateSuggestions()
    }

    private func handleSelectionChange(_ location: Int) {
        selection = NSRange(location: location, length: 0)
        updateSuggestions()
    }

    private func updateSuggestions() {
        guard canCompose, !suggestionsSuppressed else {
            suggestionItems = []
            suggestionQuery = nil
            suggestionIndex = 0
            return
        }

        let query = ComposerSuggestion.query(in: text, caret: selection.location)
        suggestionQuery = query

        guard let query else {
            suggestionItems = []
            suggestionIndex = 0
            return
        }

        suggestionItems = ComposerSuggestion.items(
            for: query,
            users: session.users.map { (id: $0.id, name: $0.name) },
            channels: session.channels.map { (id: $0.id, name: $0.name) },
            emojis: emojiCandidates,
            commands: session.pluginCommands.entries.values.flatMap { $0 }
        )

        if suggestionIndex >= suggestionItems.count {
            suggestionIndex = 0
        }
    }

    private var emojiCandidates: [EmojiCandidate] {
        let custom = session.emojis.compactMap { emoji -> EmojiCandidate? in
            guard emoji.file != nil else { return nil }
            return EmojiCandidate(name: emoji.name, glyph: "", isCustom: true)
        }
        let standard = EmojiCatalog.entries.compactMap { entry -> EmojiCandidate? in
            guard let shortcode = entry.shortcodes.first else { return nil }
            return EmojiCandidate(name: shortcode, glyph: entry.emoji, isCustom: false)
        }
        return custom + standard
    }

    private func currentSuggestionReplacement() -> (range: NSRange, text: String)? {
        guard let query = suggestionQuery, suggestionItems.indices.contains(suggestionIndex) else { return nil }
        let item = suggestionItems[suggestionIndex]
        return (NSRange(location: query.range.lowerBound, length: query.range.count), item.insert)
    }

    private func moveSuggestion(_ direction: Int) {
        guard !suggestionItems.isEmpty else { return }
        suggestionIndex = (suggestionIndex + direction + suggestionItems.count) % suggestionItems.count
    }

    private func suppressSuggestions() {
        suggestionsSuppressed = true
        suggestionItems = []
        suggestionQuery = nil
        suggestionIndex = 0
    }

    private func acceptSuggestion(at index: Int) {
        guard suggestionItems.indices.contains(index) else { return }
        suggestionIndex = index
        editor.textView?.acceptSelectedSuggestion()
    }

    private func pickFiles() {
        guard validateUpload(fileCount: attachments.count + 1) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            startUpload(panel.urls)
        }
    }

    private func startUpload(_ urls: [URL]) {
        guard editing == nil, !uploading, !sending, !urls.isEmpty else { return }
        guard validateUpload(fileCount: attachments.count + urls.count) else { return }
        uploading = true
        uploadTask = Task { await upload(urls: urls) }
    }

    private func upload(urls: [URL]) async {
        defer { uploading = false; uploadTask = nil }
        let ownerId = session.ownUserId
        let serverId = session.serverId

        for url in urls {
            do {
                try Task.checkCancellation()
                uploadName = url.lastPathComponent
                uploadProgress = 0
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard validateUpload(fileCount: attachments.count + 1, fileSize: size) else { return }
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                try Task.checkCancellation()
                guard validateUpload(fileCount: attachments.count + 1, fileSize: data.count) else { return }
                let fileId = try await session.uploadAttachment(
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream",
                    progress: { sent, total in
                        Task { @MainActor in
                            uploadProgress = total > 0 ? min(1, Double(sent) / Double(total)) : 0
                        }
                    }
                )

                guard ownerId == session.ownUserId, serverId == session.serverId else { return }
                if Task.isCancelled {
                    try await session.deleteTemporaryFile(fileId: fileId)
                    return
                }

                attachments.append(
                    PendingAttachment(id: fileId, fileId: fileId, fileName: url.lastPathComponent)
                )
                saveDraft()
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                errorMessage = SharkordSession.describe(error)
                return
            }
        }
    }

    private func validateUpload(fileCount: Int, fileSize: Int = 0) -> Bool {
        guard let rejection = AttachmentUploadPolicy.rejection(
            settings: session.settings, canSend: canSend, canUpload: session.hasPermission(.uploadFiles),
            isDM: channel.isDm, fileCount: fileCount, fileSize: fileSize
        ) else { return true }
        let key: String
        switch rejection {
        case .permission: key = "uploadPermissionDenied"
        case .disabled: key = "uploadDisabled"
        case .directMessage: key = "uploadDMDisabled"
        case .count: key = "uploadCountExceeded"
        case .size: key = "uploadSizeExceeded"
        }
        errorMessage = L10n.t(key, ns: "macos")
        return false
    }

    private func removeAttachment(_ attachment: PendingAttachment) {
        guard !sending, !removing.contains(attachment.id) else { return }
        removing.insert(attachment.id)
        let ownerId = session.ownUserId
        let serverId = session.serverId
        Task {
            defer { removing.remove(attachment.id) }
            do {
                do {
                    try await session.deleteTemporaryFile(fileId: attachment.fileId)
                } catch let error as TRPCClientError where error.code == "NOT_FOUND" {
                    // expired temporary uploads are already absent on the server
                }
                guard ownerId == session.ownUserId, serverId == session.serverId else { return }
                drafts.removeAttachment(id: attachment.id, channelId: channel.id, parentMessageId: parentMessageId)
                attachments.removeAll { $0.id == attachment.id }
                errorMessage = nil
                saveDraft()
            } catch { errorMessage = SharkordSession.describe(error) }
        }
    }

    private func saveDraft() {
        guard session.ownUserId != 0, isVisible else { return }
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

/// holds a weak reference to the live text view so the composer can drive imperative edits
/// (accepting a suggestion) that must preserve undo and caret placement.
private final class EditorHandle {
    weak var textView: ComposerTextView?
}

/// one row in the composer's suggestion menu.
private struct SuggestionRow: View {
    let item: ComposerSuggestionItem
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            leading

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 13))
                    .lineLimit(1)

                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(highlighted ? Theme.accent : .primary)
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .emoji, let glyph = item.glyph, !glyph.isEmpty {
            Text(glyph)
                .font(.system(size: 16))
                .frame(width: 16)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }

    private var iconName: String {
        switch item.kind {
        case .mention: return "person"
        case .channel: return "number"
        case .emoji: return "face.smiling"
        case .command: return "chevron.right.forwardslash.chevron.left"
        }
    }
}
