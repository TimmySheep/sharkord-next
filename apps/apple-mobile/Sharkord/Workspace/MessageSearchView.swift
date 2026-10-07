import SharkordCore
import SwiftUI

struct MessageSearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    let onOpenMessage: (Int, Int) -> Void

    @State private var query = ""
    @State private var result: SearchResult?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(L10n.t("search.placeholder"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.danger)
                } else if isSearching {
                    ProgressView(L10n.t("search.searching"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let result {
                    if result.messages.isEmpty && result.files.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: L10n.t("search.noResults"),
                            body_: L10n.t("search.tryAnother")
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if !result.messages.isEmpty {
                        SectionLabel(icon: "text.bubble", text: L10n.t("search.messages"))
                        ForEach(result.messages) { message in
                            Button {
                                open(message.channelId, message.id)
                            } label: {
                                resultCard(
                                    channelName: message.channelName,
                                    content: message.plainContent ?? MessageText.plainText(fromHTML: message.content)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !result.files.isEmpty {
                        SectionLabel(icon: "paperclip", text: L10n.t("search.files"))
                        ForEach(Array(result.files.enumerated()), id: \.offset) { _, match in
                            Button {
                                open(match.channelId, match.messageId)
                            } label: {
                                resultCard(
                                    channelName: "\(match.channelName) · \(match.file.originalName)",
                                    content: MessageText.plainText(fromHTML: match.messageContent)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if result.truncated {
                        Text(L10n.t("search.truncated"))
                            .font(.footnote)
                            .foregroundStyle(SharkordTheme.textSecondary)
                    }
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Text(L10n.t("search.minimumLength"))
                        .font(.footnote)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .background(BrandBackground())
        .navigationTitle(L10n.t("search.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 2 else {
                result = nil
                errorMessage = nil
                isSearching = false
                return
            }

            isSearching = true
            errorMessage = nil
            do {
                try await Task.sleep(for: .milliseconds(350))
                result = try await session.search(query: normalized)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func resultCard(channelName: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(channelName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SharkordTheme.accentSoft)
            Text(content.isEmpty ? L10n.t("search.attachment") : content)
                .font(.body)
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .sharkordCard(cornerRadius: 18, padding: 0)
    }

    private func open(_ channelId: Int, _ messageId: Int) {
        dismiss()
        onOpenMessage(channelId, messageId)
    }
}
