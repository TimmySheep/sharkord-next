import SharkordCore
import SwiftUI

/// A single row of inline content that wraps when it runs out of width. The web client lets
/// a paragraph wrap mid line, and a message body is a mix of styled text, inline emoji and
/// mention chips, so a plain `HStack` is not enough and `Text` cannot host images.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if rowWidth > 0, rowWidth + size.width > maxWidth {
                rows.append([])
                rowWidth = 0
            }

            rows[rows.count - 1].append(size)
            rowWidth += size.width + spacing
        }

        let height = rows.reduce(CGFloat.zero) { total, row in
            total + (row.map(\.height).max() ?? 0) + spacing
        }

        let width = rows
            .map { row in row.reduce(CGFloat.zero) { $0 + $1.width + spacing } }
            .max() ?? 0

        return CGSize(width: min(width, maxWidth), height: max(0, height - spacing))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The rendered content of one message, using the same html vocabulary the web client
/// produces (`MessageHTML.parse` is the source of truth for that vocabulary).
struct MessageBodyView: View {
    @EnvironmentObject private var session: SharkordSession

    let document: MessageDocument
    var emojiOnly: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(document.blocks) { block in
                switch block.kind {
                case .paragraph:
                    lines(of: block)
                case .code:
                    codeBlock(block)
                }
            }
        }
        .lineSpacing(3)
    }

    @ViewBuilder
    private func lines(of block: MessageBlock) -> some View {
        let grouped = Self.groupByLineBreak(block.spans)

        ForEach(Array(grouped.enumerated()), id: \.offset) { _, spans in
            FlowLayout(spacing: 3) {
                ForEach(spans) { span in
                    MessageSpanView(span: span, emojiOnly: emojiOnly)
                }
            }
        }
    }

    private func codeBlock(_ block: MessageBlock) -> some View {
        Text(block.spans.map(\.plainText).joined())
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
    }

    /// A `<br class="hard-break">` splits a paragraph into independently wrapping rows.
    static func groupByLineBreak(_ spans: [MessageSpan]) -> [[MessageSpan]] {
        var lines: [[MessageSpan]] = [[]]

        for span in spans {
            if case .lineBreak = span.content {
                lines.append([])
            } else {
                lines[lines.count - 1].append(span)
            }
        }

        return lines.filter { !$0.isEmpty }
    }
}

/// One inline run: styled text, a mention or channel chip, an emoji, or an embedded image.
struct MessageSpanView: View {
    @EnvironmentObject private var session: SharkordSession

    let span: MessageSpan
    var emojiOnly: Bool = false

    var body: some View {
        switch span.content {
        case .text(let value):
            text(value)

        case .lineBreak:
            EmptyView()

        case .mention(_, let label):
            chip(label, color: Theme.accent)

        case .channelReference(_, let label):
            chip(label, color: Theme.accent.opacity(0.85))

        case .emoji(_, let src):
            emoji(src: src)

        case .media(let src, let alt):
            media(src: src, alt: alt)

        case .pluginCommand(let name):
            chip("/\(name)", color: .purple)
        }
    }

    @ViewBuilder
    private func text(_ value: String) -> some View {
        // per run styling goes through `Text` modifiers, which compose without the
        // get-only attribute subscripts `AttributedString` exposes on this sdk
        let base = Text(value)
            .font(.system(size: emojiOnly ? 22 : 14.5))
            .tracking(0.1)
            .fontWeight(span.bold ? .semibold : .regular)

        let styled = span.italic ? base.italic() : base

        if let href = span.href, let url = URL(string: href) {
            Link(destination: url) {
                styled
                    .foregroundStyle(Theme.accent)
                    .underline()
            }
            .buttonStyle(.plain)
        } else if span.code {
            styled
                .font(.system(size: emojiOnly ? 20 : 12.5, design: .monospaced))
                .foregroundStyle(Color.pink.opacity(0.92))
                .textSelection(.enabled)
        } else {
            styled
                .textSelection(.enabled)
        }
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func emoji(src: String?) -> some View {
        let side: CGFloat = emojiOnly ? 32 : 19

        if let src, let url = session.url(forPath: src) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Text(":emoji:")
                        .font(.system(size: side * 0.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
        } else {
            Text(":emoji:")
                .font(.system(size: side * 0.5))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func media(src: String, alt: String) -> some View {
        if let url = session.url(forPath: src) {
            Link(destination: url) {
                if src.lowercased().hasSuffix(".gif") || src.lowercased().hasSuffix(".png")
                    || src.lowercased().hasSuffix(".jpg") || src.lowercased().hasSuffix(".jpeg")
                    || src.lowercased().hasSuffix(".webp") {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            placeholder(alt.isEmpty ? src : alt)
                        }
                    }
                    .frame(maxWidth: 320, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    placeholder(alt.isEmpty ? src : alt)
                }
            }
        }
    }

    private func placeholder(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(6)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
    }
}

extension MessageSpan {
    /// Plain text of a span, used for code blocks and previews.
    var plainText: String {
        switch content {
        case .text(let value):
            return value
        case .mention(_, let label):
            return label
        case .channelReference(_, let label):
            return label
        case .emoji(let name, _):
            return ":\(name):"
        case .media(_, let alt):
            return alt
        case .pluginCommand(let name):
            return "/\(name)"
        case .lineBreak:
            return "\n"
        }
    }
}

/// Attachment chip: name, type and size, opening the file in the browser on click.
struct FileCardView: View {
    @EnvironmentObject private var session: SharkordSession

    let file: SharkordFile
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if isImage, let url = session.publicFileURL(for: file) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        icon
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                icon
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.originalName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text("\(file.fileExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let url = session.publicFileURL(for: file) {
                Link(destination: url) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: 260)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
    }

    private var isImage: Bool {
        file.mimeType.hasPrefix("image/")
    }

    private var icon: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 40, height: 40)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Reaction chips under a message. Tapping one toggles the viewer's own reaction.
struct ReactionBar: View {
    @EnvironmentObject private var session: SharkordSession

    let groups: [ReactionGroup]
    var onToggle: (String) -> Void

    var body: some View {
        if !groups.isEmpty {
            HStack(spacing: 4) {
                ForEach(groups) { group in
                    Button {
                        onToggle(group.emoji)
                    } label: {
                        HStack(spacing: 4) {
                            emoji(group)

                            Text("\(group.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            group.mine ? Theme.accent.opacity(0.28) : Theme.elevated,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(group.mine ? Theme.accent : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func emoji(_ group: ReactionGroup) -> some View {
        if let file = group.file, let url = session.publicFileURL(for: file) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Text(group.emoji).font(.system(size: 12))
                }
            }
            .frame(width: 15, height: 15)
        } else {
            Text(group.emoji)
                .font(.system(size: 12))
        }
    }
}
