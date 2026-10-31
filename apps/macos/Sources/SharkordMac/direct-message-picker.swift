import SharkordCore
import SwiftUI

struct DirectMessagePicker: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var openingId: Int?
    @State private var errorMessage: String?
    @State private var openTask: Task<Void, Never>?

    private var users: [SharkordUser] {
        session.users.filter {
            $0.id != session.ownUserId && !$0.banned &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id) == query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("startNewConversation", ns: "sidebar")).font(.headline)
            TextField(L10n.t("searchUser", ns: "sidebar"), text: $query).textFieldStyle(.roundedBorder)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            if users.isEmpty { Text(L10n.t("noResults", ns: "dialogs")).foregroundStyle(.secondary) }
            List(users) { user in
                Button {
                    openingId = user.id
                    openTask = Task {
                        defer { openingId = nil }
                        do { try await session.openDirectMessage(userId: user.id); dismiss() }
                        catch {
                            guard !Task.isCancelled, !(error is CancellationError) else { return }
                            errorMessage = SharkordSession.describe(error)
                        }
                    }
                } label: {
                    HStack {
                        AvatarView(user: user, size: 28, showsPresence: true)
                        Text(user.name)
                        Text("#\(user.id)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if openingId == user.id { ProgressView().controlSize(.small) }
                    }
                }.buttonStyle(.plain).disabled(openingId != nil)
            }
            HStack { Spacer(); Button(L10n.t("cancel", ns: "common")) { dismiss() } }
        }.padding(18).frame(width: 380, height: 420)
        .onDisappear { openTask?.cancel() }
    }
}
