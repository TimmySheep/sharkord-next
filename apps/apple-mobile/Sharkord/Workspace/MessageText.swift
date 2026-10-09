import Foundation
import SharkordCore
import SwiftUI

/// Plain-text previews keep emoji shortcodes so editing a message does not silently drop them.
enum MessageText {
    static func plainText(fromHTML html: String?) -> String {
        guard let html, !html.isEmpty else {
            return ""
        }

        var text = html
        text = replacingOccurrences(of: "<br[^>]*>", in: text, with: "\n")
        text = replacingOccurrences(of: "</p>\\s*<p[^>]*>", in: text, with: "\n")
        text = replacingOccurrences(of: "</p>", in: text, with: "\n")
        text = replacingOccurrences(of: "<p[^>]*>", in: text, with: "")
        text = replacingOccurrences(of: "<img[^>]*alt=\"([^\"]*)\"[^>]*>", in: text, with: "$1")
        text = replacingOccurrences(of: "<[^>]+>", in: text, with: "")

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Server timestamps are milliseconds since the epoch.
    static func date(fromMilliseconds value: Int) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1000)
    }

    private static func replacingOccurrences(of pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

struct MessageTypingIndicator: View {
    @EnvironmentObject private var session: SharkordSession
    let channelId: Int
    var parentMessageId: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let names = session.typingUsers(in: channelId, parentMessageId: parentMessageId, now: context.date)
                .map(\.name).joined(separator: ", ")
            if !names.isEmpty {
                Text(L10n.format("channel.typing", names))
                    .font(.caption)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct MessageRichText: View {
    @EnvironmentObject private var session: SharkordSession

    let html: String

    private var document: MessageDocument {
        MessageHTML.parse(html)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(document.blocks) { block in
                MessageSpanFlowLayout(spacing: 0) {
                    ForEach(block.spans) { span in
                        MessageRichSpan(span: span)
                    }
                }
                .font(block.kind == .code ? .system(.body, design: .monospaced) : .body)
                .padding(block.kind == .code ? 8 : 0)
                .background {
                    if block.kind == .code {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SharkordTheme.field)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func MessageRichSpan(span: MessageSpan) -> some View {
        switch span.content {
        case .text(let value):
            text(value, span: span)
        case .lineBreak:
            Text("\n")
        case .mention(_, let label):
            text(label, span: span, color: SharkordTheme.accentSoft)
        case .channelReference(_, let label):
            text(label, span: span, color: SharkordTheme.accentSoft)
        case .emoji(let name, let source):
            if let source, let url = session.url(forPath: source) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(":" + name + ":")
                }
                .frame(width: 22, height: 22)
                .accessibilityLabel(":" + name + ":")
            } else {
                Text(":" + name + ":")
            }
        case .media(let source, let alt):
            if let url = session.url(forPath: source) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Text(alt)
                            .font(.caption)
                            .foregroundStyle(SharkordTheme.textSecondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 240, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(alt)
            }
        case .pluginCommand(let value):
            text(value, span: span, color: SharkordTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func text(_ value: String, span: MessageSpan, color: Color? = nil) -> some View {
        let content = styledText(value, span: span, color: color)
        if let href = span.href, let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            Link(destination: url) {
                content
                    .foregroundStyle(SharkordTheme.accentSoft)
                    .underline()
            }
        } else {
            content
        }
    }

    private func styledText(_ value: String, span: MessageSpan, color: Color?) -> Text {
        var result = Text(value)
        if span.bold {
            result = result.bold()
        }
        if span.italic {
            result = result.italic()
        }
        if span.code {
            result = result
                .font(.system(.body, design: .monospaced))
                .foregroundColor(SharkordTheme.accentSoft)
        } else if let color {
            result = result.foregroundColor(color)
        }
        return result
    }
}

private struct MessageSpanFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = makeLines(subviews: subviews, maxWidth: maxWidth)
        let width = lines.map { $0.reduce(CGFloat.zero) { $0 + $1.width } + spacing * CGFloat(max(0, $0.count - 1)) }.max() ?? 0
        let height = lines.reduce(CGFloat.zero) { $0 + ($1.map(\.height).max() ?? 0) }
            + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = makeLines(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for line in lines {
            let lineHeight = line.map(\.height).max() ?? 0
            var x = bounds.minX
            for item in line {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (lineHeight - item.height) / 2),
                    proposal: ProposedViewSize(width: item.width, height: item.height)
                )
                x += item.width + spacing
            }
            y += lineHeight + spacing
        }
    }

    private func makeLines(subviews: Subviews, maxWidth: CGFloat) -> [[CGSizeIndex]] {
        var lines: [[CGSizeIndex]] = []
        var line: [CGSizeIndex] = []
        var lineWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let nextWidth = lineWidth + (line.isEmpty ? 0 : spacing) + size.width
            if !line.isEmpty, nextWidth > maxWidth {
                lines.append(line)
                line = []
                lineWidth = 0
            }
            lineWidth += (line.isEmpty ? 0 : spacing) + size.width
            line.append(CGSizeIndex(index: index, width: size.width, height: size.height))
        }

        if !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    private struct CGSizeIndex {
        let index: Int
        let width: CGFloat
        let height: CGFloat
    }
}
