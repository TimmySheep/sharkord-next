import Combine

@MainActor
final class ComposerDrafts: ObservableObject {
    struct Draft {
        let text: String
        let attachments: [PendingAttachment]
    }

    private var drafts: [String: Draft] = [:]

    func draft(channelId: Int, parentMessageId: Int?) -> Draft? {
        drafts[key(channelId, parentMessageId)]
    }

    func save(text: String, attachments: [PendingAttachment], channelId: Int, parentMessageId: Int?) {
        let draftKey = key(channelId, parentMessageId)
        if text.isEmpty, attachments.isEmpty {
            drafts[draftKey] = nil
        } else {
            drafts[draftKey] = Draft(text: text, attachments: attachments)
        }
    }

    func clear() { drafts.removeAll() }

    func clearIfMatches(text: String, attachments: [PendingAttachment], channelId: Int, parentMessageId: Int?) {
        let draftKey = key(channelId, parentMessageId)
        guard let draft = drafts[draftKey], draft.text == text, draft.attachments == attachments else { return }
        drafts[draftKey] = nil
    }

    func removeAttachment(id: String, channelId: Int, parentMessageId: Int?) {
        guard let draft = draft(channelId: channelId, parentMessageId: parentMessageId) else { return }
        save(text: draft.text, attachments: draft.attachments.filter { $0.id != id }, channelId: channelId, parentMessageId: parentMessageId)
    }

    private func key(_ channelId: Int, _ parentMessageId: Int?) -> String {
        "\(channelId):\(parentMessageId ?? 0)"
    }
}
