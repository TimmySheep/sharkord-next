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
            Text(EmojiCatalog.glyph(for: emoji)).font(.system(size: size))
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

/// composer selections use glyphs or custom shortcodes; reactions use the web catalog identity
struct EmojiPicker: View {
    @EnvironmentObject private var session: SharkordSession

    var forReaction = false
    var onPick: (String) -> Void

    @State private var query = ""

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
                                    onPick(forReaction ? emoji.name : ":\(emoji.name):")
                                }
                                .help(emoji.name)
                                .accessibilityLabel(emoji.name)
                            }
                        } header: {
                            Eyebrow(text: L10n.t("serverEmoji", ns: "macos"))
                        }
                    }

                    ForEach(filtered, id: \.name) { entry in
                        button {
                            Text(entry.emoji).font(.system(size: 20))
                        } label: {
                            onPick(forReaction ? entry.reaction : entry.emoji)
                        }
                        .disabled(forReaction && !entry.canReact)
                        .help(forReaction && !entry.canReact ? L10n.t("reactionEmojiTooLong", ns: "macos") : entry.name)
                        .accessibilityLabel(entry.name)
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

    private var filtered: [StandardEmoji] { EmojiCatalog.search(query) }
}
