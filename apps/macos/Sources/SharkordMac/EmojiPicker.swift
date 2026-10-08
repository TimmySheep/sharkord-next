import SharkordCore
import SwiftUI

/// Emoji rendering shared by reactions and the picker: a custom server emoji is an image,
/// a standard one is the character itself.
struct EmojiView: View {
    @EnvironmentObject private var session: SharkordSession

    let emoji: String
    let file: SharkordFile?
    var size: CGFloat = 14

    var body: some View {
        if let file, let url = session.publicFileURL(for: file) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        } else {
            Text(emoji).font(.system(size: size))
        }
    }
}

/// "React" submenu used from a message's context menu.
struct ReactionMenu: View {
    @EnvironmentObject private var session: SharkordSession

    let message: SharkordMessage

    /// A few always-available reactions, as the server stores them: the GitHub shortcode for
    /// standard emoji, the emoji name for custom ones.
    private static let commonEmoji = ["thumbsup", "heart", "joy", "tada", "fire", "eyes", "sob"]

    var body: some View {
        Menu {
            ForEach(session.emojis) { emoji in
                Button(emoji.name) {
                    react(emoji.name)
                }
            }

            if !session.emojis.isEmpty {
                Divider()
            }

            ForEach(Self.commonEmoji, id: \.self) { name in
                Button(name) {
                    react(name)
                }
            }
        } label: {
            Label(L10n.t("addReaction", ns: "common"), systemImage: "face.smiling")
        }
    }

    private func react(_ emoji: String) {
        Task {
            try? await session.toggleReaction(messageId: message.id, emoji: emoji)
        }
    }
}

/// One reaction chip under a message.
struct ReactionChip: View {
    @EnvironmentObject private var session: SharkordSession

    let group: ReactionGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                EmojiView(emoji: group.emoji, file: group.file)

                Text("\(group.count)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                group.mine ? Theme.accent.opacity(0.35) : Theme.elevated,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(group.mine ? Theme.accent : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Picker for the composer: the server's custom emoji first, then a standard set. Custom
/// emoji insert their `:name:` shortcode, which the composer turns into an emoji element
/// when it builds the message html.
struct EmojiPicker: View {
    @EnvironmentObject private var session: SharkordSession

    var onPick: (String) -> Void

    @State private var query = ""

    /// A compact standard set, enough for chat without shipping a whole emoji font index.
    private static let standard: [(name: String, char: String)] = [
        ("smile", "😄"), ("joy", "😂"), ("heart", "❤️"), ("thumbsup", "👍"),
        ("thumbsdown", "👎"), ("tada", "🎉"), ("fire", "🔥"), ("eyes", "👀"),
        ("wave", "👋"), ("thinking", "🤔"), ("sob", "😭"), ("pray", "🙏"),
        ("rocket", "🚀"), ("star", "⭐"), ("warning", "⚠️"), ("check", "✅"),
        ("x", "❌"), ("100", "💯"), ("clap", "👏"), ("muscle", "💪"),
        ("sparkles", "✨"), ("cake", "🎂"), ("coffee", "☕"), ("pizza", "🍕"),
        ("sun", "☀️"), ("moon", "🌙"), ("rainbow", "🌈"), ("dog", "🐶"),
        ("cat", "🐱"), ("unicorn", "🦄"), ("shrug", "🤷"), ("sleeping", "😴")
    ]

    var body: some View {
        VStack(spacing: 8) {
            TextField(L10n.t("searchEmojisPlaceholder", ns: "settings"), text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 6)], spacing: 6) {
                    if !custom.isEmpty {
                        Section {
                            ForEach(custom) { emoji in
                                button {
                                    if let file = emoji.file, let url = session.publicFileURL(for: file) {
                                        AsyncImage(url: url) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFit()
                                            }
                                        }
                                        .frame(width: 22, height: 22)
                                    } else {
                                        Text(":")
                                            .foregroundStyle(.secondary)
                                    }
                                } label: {
                                    onPick(":\(emoji.name):")
                                }
                            }
                        } header: {
                            Eyebrow(text: "Server")
                        }
                    }

                    ForEach(filtered, id: \.name) { entry in
                        button {
                            Text(entry.char).font(.system(size: 20))
                        } label: {
                            onPick(entry.char)
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    private func button<Content: View>(
        @ViewBuilder content: () -> Content,
        label: @escaping () -> Void
    ) -> some View {
        Button(action: label) {
            content()
                .frame(width: 32, height: 32)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var custom: [SharkordEmoji] {
        guard !query.isEmpty else {
            return session.emojis
        }

        return session.emojis.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var filtered: [(name: String, char: String)] {
        guard !query.isEmpty else {
            return Self.standard
        }

        return Self.standard.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
