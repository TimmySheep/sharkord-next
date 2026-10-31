import SwiftUI

/// Watch-scale design tokens. Same visual language as the iPhone client (pure black,
/// rounded dark cards, electric blue primary) re-sized for a ~200pt wrist screen.
enum WatchTheme {
    static let background = Color(red: 0, green: 0, blue: 0)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.118)
    static let field = Color(red: 0.173, green: 0.173, blue: 0.18)
    static let accent = Color(red: 0.169, green: 0.361, blue: 0.91)
    static let accentSoft = Color(red: 0.361, green: 0.549, blue: 1)
    static let danger = Color(red: 0.878, green: 0.322, blue: 0.322)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.62)

    static let cardCorner: CGFloat = 18
    static let fieldCorner: CGFloat = 12
}

/// Rounded dark container used by every screen block.
struct WatchCard<Content: View>: View {
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: WatchTheme.cardCorner, style: .continuous))
    }

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

struct WatchBrandMark: View {
    let size: CGFloat

    var body: some View {
        Image("CoveLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Small status pill: connected / listening / transmitting. Dot plus label.
struct WatchStatePill: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(WatchTheme.card, in: Capsule())
    }
}
