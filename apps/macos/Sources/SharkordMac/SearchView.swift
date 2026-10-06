import SharkordCore
import SwiftUI

/// Server search over messages and files. Debounced, and it reports when the server
/// truncated the result set, matching the web client's search dialog.
struct SearchView: View {
    @EnvironmentObject private var session: SharkordSession

    var onJump: (_ messageId: Int, _ channelId: Int) -> Void

    @State private var query = ""
    @State private var result: SearchResult?
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.t("searchPlaceholder", ns: "macos"), text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await search() } }

                if searching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(14)

            Divider()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(14)
            } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                placeholder(L10n.t("typeAtLeast2", ns: "macos"))
            } else if let result, result.messages.isEmpty, result.files.isEmpty {
                placeholder(L10n.t("noResults", ns: "dialogs"))
            } else if let result {
                resultList(result)
            } else {
                placeholder(L10n.t("searchPlaceholder", ns: "macos"))
            }
        }
        .background(Theme.panel)
        .onChange(of: query) {
            task?.cancel()
            task = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)

                guard !Task.isCancelled else {
                    return
                }

                await search()
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultList(_ result: SearchResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if result.truncated {
                    Text(L10n.t("searchTruncated", ns: "macos"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }

                ForEach(result.messages) { message in
                    Button {
                        onJump(message.id, message.channelId)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(message.channelIsDm ? "Direct message" : "#\(message.channelName)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Theme.accent)

                                Text(
                                    Date(timeIntervalSince1970: Double(message.createdAt) / 1000),
                                    style: .relative
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                                Spacer()
                            }

                            Text(message.plainContent ?? MessageHTML.toPlainText(message.content ?? ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(8)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(result.files, id: \.file.id) { entry in
                    Button {
                        onJump(entry.messageId, entry.channelId)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.file.originalName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)

                                Text(entry.channelIsDm ? "Direct message" : "#\(entry.channelName)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(8)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        guard trimmed.count >= 2 else {
            result = nil
            errorMessage = nil

            return
        }

        searching = true
        defer { searching = false }

        do {
            result = try await session.search(query: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = SharkordSession.describe(error)
        }
    }
}
