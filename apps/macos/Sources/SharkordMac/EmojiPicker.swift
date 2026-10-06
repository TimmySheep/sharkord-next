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
            Label("React", systemImage: "face.smiling")
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
                Capsule().stroke(group.mine ? Theme.accent : .white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
