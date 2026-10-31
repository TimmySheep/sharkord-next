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

    private func key(_ channelId: Int, _ parentMessageId: Int?) -> String {
        "\(channelId):\(parentMessageId ?? 0)"
    }
}
